#include "document.hpp"
#include <QRegularExpression>
#include <QXmlStreamReader>
#include <functional>

namespace hyui {
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

}
