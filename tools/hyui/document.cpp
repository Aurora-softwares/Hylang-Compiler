#include "document.hpp"
#include <QRegularExpression>
#include <QDir>
#include <QFileInfo>
#include <stdexcept>
#include <QXmlStreamReader>
#include <functional>

namespace hyui {
static const QMap<QString, QSet<QString>> attributes = {
    {"Window", {"version", "title", "width", "height", "padding", "theme", "onLoad", "material"}},
    {"ColumnPanel", {"gap"}}, {"RowPanel", {"gap", "breakpoint"}},
    {"GridPanel", {"gap", "columns", "minItemWidth"}},
    {"Panel", {"title", "padding", "gap"}},
    {"MenuBar", {}}, {"Menu", {"text"}}, {"MenuItem", {"text", "onClick", "checked"}},
    {"Tabs", {"value", "onChange"}}, {"Tab", {"title", "gap"}},
    {"ListBox", {"items", "value", "height", "onChange"}},
    {"Table", {"columns", "rows", "value", "height", "onChange"}},
    {"RadioGroup", {"items", "value", "onChange"}},
    {"Image", {"source", "height"}},
    {"Dialog", {"title", "text", "buttons", "open", "value", "onClose"}},
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
static const QSet<QString> booleans = {"visible", "enabled", "fill", "primary", "checked", "running", "indeterminate", "open"};
static const QSet<QString> numbers = {"width", "height", "padding", "gap", "breakpoint", "columns", "minItemWidth",
                                      "preferredWidth", "minimum", "maximum", "interval"};
static bool container(const QString& tag) {
    return tag == "Tabs" || tag == "Tab" || tag == "MenuBar" || tag == "Menu" || tag == "Window" || tag == "Panel" || tag == "ColumnPanel" || tag == "RowPanel" || tag == "GridPanel";
}

QString Document::resourcePath(const QString& relative) const {
    const QString root = QFileInfo(sourcePath).absoluteDir().canonicalPath();
    const QString file = QFileInfo(QDir(root).filePath(relative)).canonicalFilePath();
    if (root.isEmpty() || file.isEmpty() || !file.startsWith(root + '/') || !QFileInfo(file).isFile()) { throw std::runtime_error("image asset is missing or outside the document directory"); }
    return file;
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
            if ((numbers.contains(key) && !(key == "columns" && node.tag == "Table")) || (key == "value" && node.tag != "State")) {
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
        for (const QString& prop : {"text", "value", "checked", "running", "indeterminate", "open"}) {
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
            int maximum = node.attributes.value("maximum", "100").toInt();
            if (node.tag == "Select" || node.tag == "ListBox" || node.tag == "RadioGroup") { maximum = node.attributes.value("items").split('|').size() - 1; }
            if (node.tag == "Table") { maximum = node.attributes.value("rows").split('\n').size() - 1; }
            if (node.tag == "Dialog") { maximum = node.attributes.value("buttons", "OK").split('|').size() - 1; }
            if (node.tag == "Tabs") { maximum = 32767; } // Child count is checked after parsing.
            int value = initialState[node.id + ".value"].toInt();
            if (value < minimum || value > maximum) { return invalid("value is outside the control's range"); }
            ranges[node.id] = qMakePair(minimum, maximum);
        }
        if (node.tag == "Timer" && !node.attributes.contains("onTick")) { return invalid("Timer requires onTick"); }
        while (!reader.atEnd()) {
            auto token = reader.readNext();
            if (token == QXmlStreamReader::StartElement) {
                if (!container(node.tag)) { return invalid(node.tag + " cannot have children"); }
                const QString childTag = reader.name().toString();
                if ((node.tag == "Tabs" && childTag != "Tab") || (node.tag == "MenuBar" && childTag != "Menu") ||
                    (node.tag == "Menu" && childTag != "MenuItem") ||
                    (childTag == "Tab" && node.tag != "Tabs") || (childTag == "Menu" && node.tag != "MenuBar") ||
                    (childTag == "MenuItem" && node.tag != "Menu") || (childTag == "MenuBar" && node.tag != "Window") ||
                    (childTag == "Dialog" && node.tag != "Window")) { return invalid("invalid placement of " + childTag); }
                Node child;
                if (!read(child, depth + 1)) { return false; }
                node.children.push_back(std::move(child));
            } else if (token == QXmlStreamReader::EndElement) {
                if (node.tag == "Window") {
                    int menus = 0; for (const Node& child : node.children) { if (child.tag == "MenuBar") { ++menus; } }
                    if (menus > 1) { return invalid("Window permits one MenuBar"); }
                }
                if (node.tag == "Tabs") {
                    if (node.children.empty() || initialState[node.id + ".value"].toInt() >= int(node.children.size())) { return invalid("Tabs requires pages and a valid selected value"); }
                    ranges[node.id] = qMakePair(0, int(node.children.size()) - 1);
                }
                if ((node.tag == "ListBox" || node.tag == "RadioGroup") && node.attributes.value("items").isEmpty()) { return invalid(node.tag + " requires items"); }
                if (node.tag == "Table") {
                    const auto columns = node.attributes.value("columns").split('|');
                    if (node.attributes.value("columns").isEmpty() || node.attributes.value("rows").isEmpty()) { return invalid("Table requires columns and rows"); }
                    for (const auto& row : node.attributes.value("rows").split('\n')) { if (row.split('|').size() != columns.size()) { return invalid("Table row must match column count"); } }
                }
                if (node.tag == "Dialog" && (node.attributes.value("buttons", "OK").isEmpty() || node.attributes.value("buttons", "OK").split('|').size() > 3)) { return invalid("Dialog requires one to three buttons"); }
                if (node.tag == "Image") {
                    QString source = node.attributes.value("source");
                    if (source.isEmpty() || QDir::isAbsolutePath(source) || source.contains(':') || source.contains('\\') || source.split('/').contains("..")) { return invalid("Image source must be a relative asset path"); }
                }
                return true;
            }
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
