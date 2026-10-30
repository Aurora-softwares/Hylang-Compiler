#include "document.hpp"
#include <QColor>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QXmlStreamReader>
#include <functional>

namespace hyui {
QString quote(const QString& value) {
    QByteArray json = QJsonDocument(QJsonArray{value}).toJson(QJsonDocument::Compact);
    return QString::fromUtf8(json.mid(1, json.size() - 2));
}

static const QMap<QString, QSet<QString>> attributes = {
    {"Window", {"version", "title", "width", "height", "padding", "theme", "onLoad", "material"}},
    {"ColumnPanel", {"gap"}}, {"RowPanel", {"gap", "breakpoint"}},
    {"GridPanel", {"gap", "columns", "minItemWidth"}},
    {"Panel", {"title", "padding", "gap"}},
    {"Label", {"text", "role", "tone"}},
    {"Button", {"text", "onClick", "primary"}},
    {"Input", {"text", "placeholder", "onChange", "onSubmit"}},
    {"TextArea", {"text", "placeholder", "onChange", "height"}},
    {"CheckBox", {"text", "checked", "onChange"}},
    {"Switch", {"text", "checked", "onChange"}},
    {"Select", {"items", "value", "onChange"}},
    {"Slider", {"value", "minimum", "maximum", "onChange"}},
    {"NumberInput", {"value", "minimum", "maximum", "onChange"}},
    {"ProgressBar", {"value", "minimum", "maximum", "indeterminate"}},
    {"Spinner", {"running"}}, {"Separator", {}}, {"Spacer", {"height"}},
    {"State", {"value"}}, {"Timer", {"interval", "running", "onTick"}}
};
static const QSet<QString> common = {"id", "visible", "enabled", "fill", "preferredWidth", "accessibleName"};
static const QSet<QString> booleans = {"visible", "enabled", "fill", "primary", "checked", "running", "indeterminate"};
static const QSet<QString> numbers = {"width", "height", "padding", "gap", "breakpoint", "columns", "minItemWidth",
                                      "preferredWidth", "minimum", "maximum", "interval"};
static bool container(const QString& tag) {
    return tag == "Window" || tag == "Panel" || tag == "ColumnPanel" || tag == "RowPanel" || tag == "GridPanel";
}

bool Document::parse(const QByteArray& xml) {
    error.clear(); initialState.clear(); properties.clear(); handlers.clear(); ranges.clear(); window = {};
    if (xml.size() > 1024 * 1024) { error = "HYUI documents are limited to 1 MiB"; return false; }
    QXmlStreamReader reader(xml);
    QSet<QString> ids;
    int count = 0;
    auto invalid = [&](const QString& message) {
        error = QString("line %1: %2").arg(reader.lineNumber()).arg(message);
        return false;
    };
    std::function<bool(Node&, int)> read = [&](Node& node, int depth) {
        if (depth > 32 || ++count > 512) { return invalid("maximum nesting (32) or element count (512) exceeded"); }
        node.tag = reader.name().toString();
        if (!reader.namespaceUri().isEmpty() || !reader.prefix().isEmpty() || !attributes.contains(node.tag)) {
            return invalid("unknown element '" + reader.qualifiedName().toString() + "'");
        }
        if ((depth == 0) != (node.tag == "Window")) { return invalid("exactly one root Window is required"); }
        for (const auto& attr : reader.attributes()) {
            QString key = attr.qualifiedName().toString(), value = attr.value().toString();
            const bool visual = node.tag != "Window" && node.tag != "Timer" && node.tag != "State";
            if (!attributes[node.tag].contains(key) && !(key == "id" || (visual && common.contains(key)))) {
                return invalid("unknown attribute '" + key + "' on " + node.tag);
            }
            if (value.size() > 16384) { return invalid("attribute exceeds 16384 characters"); }
            if (booleans.contains(key) && value != "true" && value != "false") { return invalid(key + " must be true or false"); }
            if (numbers.contains(key) || (key == "value" && node.tag != "State")) {
                bool ok = false; int n = value.toInt(&ok);
                if (!ok || n < 0 || n > 32767 || ((key == "columns" || key == "minItemWidth" || key == "width" || key == "height") && n == 0)) {
                    return invalid(key + " must be an integer in its supported range (0..32767)");
                }
                if (key == "interval" && n < 100) { return invalid("Timer interval must be at least 100 ms"); }
            }
            if (key.startsWith("on") && !QRegularExpression("^[A-Za-z_][A-Za-z0-9_.]{0,127}$").match(value).hasMatch()) {
                return invalid("invalid handler name");
            }
            node.attributes.insert(key, value);
        }
        if (node.tag == "Window" && node.attributes.value("version") != "1") { return invalid("Window requires version=\"1\""); }
        if (node.attributes.contains("theme") && !QStringList{"system", "light", "dark"}.contains(node.attributes["theme"])) {
            return invalid("theme must be system, light, or dark");
        }
        if (node.attributes.contains("material") && !QStringList{"auto", "glass", "solid"}.contains(node.attributes["material"])) {
            return invalid("material must be auto, glass, or solid");
        }
        if (node.attributes.contains("role") && !QStringList{"title", "heading", "body", "caption"}.contains(node.attributes["role"])) {
            return invalid("unknown Label role");
        }
        if (node.attributes.contains("tone") && !QStringList{"normal", "muted", "accent"}.contains(node.attributes["tone"])) {
            return invalid("unknown Label tone");
        }
        node.id = node.attributes.value("id", "_hyui" + QString::number(count));
        if (!QRegularExpression("^[A-Za-z_][A-Za-z0-9_]{0,63}$").match(node.id).hasMatch() || ids.contains(node.id)) {
            return invalid("invalid or duplicate id '" + node.id + "'");
        }
        ids.insert(node.id);
        QSet<QString> props;
        if (node.tag != "Window" && node.tag != "Timer" && node.tag != "State") { props = {"visible", "enabled"}; }
        for (const QString& prop : {"text", "value", "checked", "running", "indeterminate"}) {
            if (attributes[node.tag].contains(prop)) { props.insert(prop); }
        }
        properties.insert(node.id, props);
        for (const auto& prop : props) {
            QString value = node.attributes.value(prop);
            if (prop == "enabled" || prop == "visible") { value = node.attributes.value(prop, "true"); }
            if (prop == "running") { value = node.attributes.value(prop, node.tag == "Spinner" ? "true" : "false"); }
            QVariant typed = value;
            if (booleans.contains(prop)) { typed = value == "true"; }
            if (prop == "value" && node.tag != "State") { typed = value.isEmpty() ? 0 : value.toInt(); }
            initialState.insert(node.id + "." + prop, typed);
        }
        for (auto it = node.attributes.cbegin(); it != node.attributes.cend(); ++it) {
            if (it.key().startsWith("on")) { handlers[it.value()].insert(node.id); }
        }
        if (node.attributes.value("maximum", "100").toInt() < node.attributes.value("minimum", "0").toInt()) {
            return invalid("maximum must be greater than or equal to minimum");
        }
        if (props.contains("value") && node.tag != "State") {
            int minimum = node.attributes.value("minimum", "0").toInt();
            int maximum = node.tag == "Select" ? node.attributes.value("items").split('|').size() - 1 : node.attributes.value("maximum", "100").toInt();
            int value = initialState[node.id + ".value"].toInt();
            if (value < minimum || value > maximum) { return invalid("value is outside the control's range"); }
            ranges[node.id] = qMakePair(minimum, maximum);
        }
        if (node.tag == "Timer" && !node.attributes.contains("onTick")) { return invalid("Timer requires onTick"); }
        while (!reader.atEnd()) {
            auto token = reader.readNext();
            if (token == QXmlStreamReader::StartElement) {
                if (!container(node.tag)) { return invalid(node.tag + " cannot have children"); }
                Node child;
                if (!read(child, depth + 1)) { return false; }
                node.children.push_back(std::move(child));
            } else if (token == QXmlStreamReader::EndElement) { return true; }
            else if (token == QXmlStreamReader::DTD || token == QXmlStreamReader::EntityReference) { return invalid("DTD and entities are not supported"); }
            else if (token == QXmlStreamReader::Characters && !reader.isWhitespace()) { return invalid("use the text attribute for content"); }
        }
        return false;
    };
    bool found = false;
    while (!reader.atEnd()) {
        auto token = reader.readNext();
        if (token == QXmlStreamReader::DTD || token == QXmlStreamReader::EntityReference) { return invalid("DTD and entities are not supported"); }
        if (token == QXmlStreamReader::StartElement) {
            if (found) { return invalid("multiple root elements"); }
            found = true;
            if (!read(window, 0)) { if (error.isEmpty()) { error = reader.errorString(); } return false; }
        }
    }
    if (reader.hasError()) { return invalid(reader.errorString()); }
    if (!found) { return invalid("missing Window"); }
    return true;
}

QString Document::emitNode(const Node& n, int depth) const {
    const auto& a = n.attributes;
    auto number = [&](const QString& key, const QString& fallback) { return a.value(key, fallback); };
    auto state = [&](const QString& key) { return "bridge.state[" + quote(n.id + "." + key) + "]"; };
    auto action = [&](const QString& key) {
        return a.contains(key) ? "bridge.dispatch(" + quote(a[key]) + ", " + quote(n.id) + ");" : QString();
    };
    if (n.tag == "State") { return {}; }
    if (n.tag == "Timer") {
        return "Timer { interval: " + number("interval", "1000") + "; repeat: true; running: " + state("running") +
            "; onTriggered: { " + action("onTick") + " } }\n";
    }
    static const QMap<QString, QString> types = {{"ColumnPanel", "ColumnLayout"}, {"RowPanel", "GridLayout"},
        {"GridPanel", "GridLayout"}, {"Panel", "Frame"}, {"Label", "Label"}, {"Input", "TextField"},
        {"TextArea", "TextArea"}, {"Button", "Button"}, {"CheckBox", "CheckBox"}, {"Switch", "Switch"},
        {"Select", "ComboBox"}, {"Slider", "Slider"}, {"NumberInput", "SpinBox"}, {"ProgressBar", "ProgressBar"},
        {"Spinner", "BusyIndicator"}, {"Separator", "Rectangle"}, {"Spacer", "Item"}};
    QString result = types.value(n.tag) + " {\nobjectName: " + quote(n.id) + ";\n";
    result += "Layout.minimumWidth: 0; Layout.fillWidth: " + a.value("fill", n.tag == "Button" || n.tag == "Spinner" ? "false" : "true") + ";\n";
    if (a.contains("preferredWidth")) { result += "Layout.preferredWidth: " + a["preferredWidth"] + ";\n"; }
    result += "visible: " + state("visible") + "; enabled: " + state("enabled") + ";\n";
    if (a.contains("accessibleName")) { result += "Accessible.name: " + quote(a["accessibleName"]) + ";\n"; }
    if (properties[n.id].contains("text")) { result += "text: " + state("text") + ";\n"; }
    if (properties[n.id].contains("checked")) {
        result += "checked: " + state("checked") + "; onToggled: { bridge.store(" + quote(n.id) + ", \"checked\", checked); " + action("onChange") + " }\n";
    }
    if (n.tag == "ColumnPanel") { result += "spacing: " + number("gap", "12") + ";\n"; }
    if (n.tag == "RowPanel" || n.tag == "GridPanel") {
        int visual = 0;
        for (const auto& child : n.children) { if (child.tag != "State" && child.tag != "Timer") { ++visual; } }
        QString columns = n.tag == "RowPanel" ? "(width < " + number("breakpoint", "700") + " ? 1 : " + QString::number(qMax(1, visual)) + ")" :
            "Math.max(1, Math.min(" + number("columns", "3") + ", Math.floor((width + columnSpacing) / (" + number("minItemWidth", "240") + " + columnSpacing))))";
        result += "columns: " + columns + "; columnSpacing: " + number("gap", "16") + "; rowSpacing: " + number("gap", "16") + ";\n";
    }
    if (n.tag == "Panel") {
        result += "padding: " + number("padding", "22") + ";\n";
        result += "background: Rectangle { color: root.palette.base; radius: 14; border.color: root.palette.mid; border.width: 1 }\n";
        result += "contentItem: ColumnLayout { spacing: " + number("gap", "12") + ";\n";
        if (a.contains("title")) { result += "Label { text: " + quote(a["title"]) + "; font.bold: true; font.pixelSize: 17; textFormat: Text.PlainText; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.minimumWidth: 0 }\n"; }
    }
    if (n.tag == "Label") {
        const QString role = a.value("role", "body");
        result += "textFormat: Text.PlainText; wrapMode: Text.Wrap;\n";
        result += "font.pixelSize: " + QString(role == "title" ? "32" : role == "heading" ? "19" : role == "caption" ? "12" : "14") + ";\n";
        if (role == "title" || role == "heading") { result += "font.bold: true;\n"; }
        if (a.value("tone") == "muted") { result += "color: root.palette.placeholderText;\n"; }
        if (a.value("tone") == "accent") { result += "color: root.palette.highlight;\n"; }
    }
    if (n.tag == "Button") { result += "highlighted: " + a.value("primary", "false") + "; onClicked: { " + action("onClick") + " }\n"; }
    if (n.tag == "Input" || n.tag == "TextArea") {
        result += "placeholderText: " + quote(a.value("placeholder")) + "; selectByMouse: true;\n";
        if (n.tag == "TextArea") { result += "property bool hyuiReady: false; Component.onCompleted: hyuiReady = true;\n"; }
        QString guard = n.tag == "TextArea" ? "if (hyuiReady && !bridge.isApplying()) " : "";
        result += (n.tag == "Input" ? "onTextEdited" : "onTextChanged") + QString(": { ") + guard + "{ bridge.store(" + quote(n.id) + ", \"text\", text); " + action("onChange") + " } }\n";
        if (n.tag == "Input") { result += "onAccepted: { " + action("onSubmit") + " }\n"; }
        else { result += "wrapMode: TextEdit.Wrap; Layout.preferredHeight: " + number("height", "100") + ";\n"; }
    }
    if (n.tag == "Select") {
        QJsonArray items;
        for (const auto& item : a.value("items").split('|')) { items.append(item); }
        result += "model: " + QString::fromUtf8(QJsonDocument(items).toJson(QJsonDocument::Compact)) + ";\n";
        result += "currentIndex: " + state("value") + "; onActivated: { bridge.store(" + quote(n.id) + ", \"value\", currentIndex); " + action("onChange") + " }\n";
    }
    if (n.tag == "Slider" || n.tag == "NumberInput" || n.tag == "ProgressBar") {
        result += "from: " + number("minimum", "0") + "; to: " + number("maximum", "100") + "; value: " + state("value") + ";\n";
        if (n.tag != "ProgressBar") {
            result += (n.tag == "Slider" ? "stepSize: 1; onMoved" : "editable: true; onValueModified") +
                QString(": { bridge.store(") + quote(n.id) + ", \"value\", value); " + action("onChange") + " }\n";
        } else { result += "indeterminate: " + state("indeterminate") + ";\n"; }
    }
    if (n.tag == "Spinner") { result += "running: " + state("running") + "; Layout.preferredWidth: 28; Layout.preferredHeight: 28;\n"; }
    if (n.tag == "Separator") { result += "implicitHeight: 1; color: root.palette.mid;\n"; }
    if (n.tag == "Spacer") { result += "implicitHeight: " + number("height", "12") + ";\n"; }
    for (const auto& child : n.children) { result += emitNode(child, depth + 1); }
    if (n.tag == "Panel") { result += "}\n"; }
    return result + "}\n";
}

QString Document::qml() const {
    QString result = "import QtQuick\nimport QtQuick.Controls\nimport QtQuick.Layouts\nApplicationWindow {\nid: root; visible: false;\n";
    result += "title: " + quote(window.attributes.value("title", "Hydrogen")) + ";\n";
    result += "width: " + window.attributes.value("width", "1100") + "; height: " + window.attributes.value("height", "820") + ";\n";
    // No fixed minimum window size: small monitors remain usable by reflow and scrolling.
    result += "ScrollView { id: scroll; anchors.fill: parent; clip: true; contentWidth: availableWidth;\n";
    result += "Pane { width: scroll.availableWidth; padding: Math.min(" + window.attributes.value("padding", "28") + ", Math.max(8, width / 25));\n";
    result += "contentItem: ColumnLayout { spacing: 20;\n";
    for (const auto& child : window.children) { result += emitNode(child, 0); }
    result += "}\n}\n}\n";
    result += "footer: ToolBar { visible: bridge.error.length > 0; Label { width: parent.width; padding: 10; wrapMode: Text.Wrap; textFormat: Text.PlainText; text: bridge.error; color: root.palette.text } }\n";
    result += "}\n";
    return result;
}
}
