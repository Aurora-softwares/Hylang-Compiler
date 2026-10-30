#include "bridge.hpp"
#include <QRegularExpression>

namespace hyui {
Bridge::Bridge(const Document& doc, QString executable, QString cwd, QObject* parent)
    : QObject(parent), document(doc), values(doc.initialState), backend(std::move(executable)), directory(std::move(cwd)) {
    timeout.setSingleShot(true);
    connect(&timeout, &QTimer::timeout, this, [this] { fail("Hydrogen handler timed out (10 seconds)"); process.kill(); });
    connect(&process, &QProcess::readyReadStandardOutput, this, [this] {
        output += process.readAllStandardOutput();
        if (output.size() > 1024 * 1024) { overflow = true; fail("Hydrogen handler output exceeds 1 MiB"); process.kill(); }
    });
    connect(&process, &QProcess::readyReadStandardError, this, [this] {
        errors += process.readAllStandardError();
        if (errors.size() > 65536) { overflow = true; fail("Hydrogen handler error output exceeds 64 KiB"); process.kill(); }
    });
    connect(&process, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        timeout.stop();
        output += process.readAllStandardOutput(); errors += process.readAllStandardError();
        if (!overflow) {
            if (status != QProcess::NormalExit || code != 0) { fail("Hydrogen handler failed: " + QString::fromUtf8(errors.left(4096))); }
            else { apply(output); }
        }
        active = false; emit busyChanged();
        QTimer::singleShot(0, this, [this] { next(); });
    });
    connect(&process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            timeout.stop(); fail("Cannot start Hydrogen backend: " + process.errorString());
            active = false; emit busyChanged(); emit idle();
        }
    });
}

QString Bridge::encode(QString value) {
    return value.replace('%', "%25").replace('\t', "%09").replace('\r', "%0D").replace('\n', "%0A");
}
QString Bridge::decode(QString value) {
    return value.replace("%09", "\t").replace("%0D", "\r").replace("%0A", "\n").replace("%25", "%");
}
void Bridge::fail(const QString& message) { lastError = message; emit errorChanged(); }

void Bridge::store(const QString& id, const QString& property, const QVariant& value) {
    if (!document.properties.value(id).contains(property)) { return; }
    // Do not notify on a keystroke: the editor owns its cursor and selection.
    // Backend updates notify all declarative bindings after the response commits.
    values[id + "." + property] = value;
}

bool Bridge::apply(const QByteArray& response) {
    if (response.size() > 1024 * 1024) { fail("Hydrogen response exceeds 1 MiB"); return false; }
    QVariantMap updated = values;
    for (QByteArray raw : response.split('\n')) {
        if (raw.endsWith('\r')) { raw.chop(1); }
        if (!raw.startsWith("HYUI\t")) { continue; }
        const auto parts = QString::fromUtf8(raw).split('\t');
        if (parts.size() == 3 && parts[1] == "OPEN") { continue; }
        if (parts.size() != 5 || parts[1] != "SET") { fail("Malformed HYUI backend response"); return false; }
        const QString id = decode(parts[2]), property = decode(parts[3]), text = decode(parts[4]);
        if (!document.properties.value(id).contains(property)) { fail("Backend tried to update an unknown control or property: " + id + "." + property); return false; }
        const QString key = id + "." + property;
        QVariant typed = text;
        if (document.initialState[key].metaType().id() == QMetaType::Bool) {
            if (text != "true" && text != "false") { fail("Backend boolean must be true or false"); return false; }
            typed = text == "true";
        }
        if (document.initialState[key].metaType().id() == QMetaType::Int) {
            bool ok = false; int number = text.toInt(&ok);
            if (!ok || number < 0 || number > 32767) { fail("Backend number must be in 0..32767"); return false; }
            const auto range = document.ranges.value(id, qMakePair(0, 32767));
            if (number < range.first || number > range.second) { fail("Backend value is outside the control's range"); return false; }
            typed = number;
        }
        updated[key] = typed;
    }
    values = std::move(updated);
    // A stopped timer must not leave an already queued tick behind a cancel
    // or completion response.
    for (int i = pending.size() - 1; i >= 0; --i) {
        const QString key = pending[i].second + ".running";
        if (values.contains(key) && !values[key].toBool()) { pending.removeAt(i); }
    }
    lastError.clear(); emit errorChanged();
    applying = true;
    emit changed();
    applying = false;
    return true;
}

void Bridge::dispatch(const QString& handler, const QString& sender) {
    if (!document.handlers.value(handler).contains(sender)) { fail("Unregistered Hydrogen handler: " + handler); return; }
    const QPair<QString, QString> event(handler, sender);
    if (pending.contains(event)) { return; }
    if (pending.size() >= 32) { fail("Too many queued Hydrogen events"); return; }
    pending.enqueue(event);
    next();
}

void Bridge::next() {
    if (active) { return; }
    if (pending.isEmpty()) { emit idle(); return; }
    const auto event = pending.dequeue();
    QStringList args = {"--hyui-event", event.first, event.second};
    int size = 0;
    for (auto it = document.properties.cbegin(); it != document.properties.cend(); ++it) {
        QString prop;
        if (it.value().contains("value")) { prop = "value"; }
        else if (it.value().contains("checked")) { prop = "checked"; }
        else if (it.value().contains("text")) { prop = "text"; }
        if (prop.isEmpty()) { continue; }
        QString value = values.value(it.key() + "." + prop).toString();
        size += it.key().size() + value.size() + 6;
        args << it.key() << value;
    }
    if (size > 24000) { fail("UI value snapshot exceeds 24000 characters"); pending.clear(); emit idle(); return; }
    output.clear(); errors.clear(); overflow = false; active = true; emit busyChanged();
    process.setWorkingDirectory(directory);
    // QProcess receives an argument vector. User text never passes through a shell.
    process.start(backend, args);
    timeout.start(10000);
}
}
