#include "bridge.hpp"
#include "document.hpp"
#include <QCoreApplication>
#include <QFile>
#include <QtTest>
#include <iostream>
#include <functional>
#include "element_contract_cases.hpp"

class HyuiTests : public QObject {
    Q_OBJECT
private slots:

    // Each of the 43 public HYUI elements is a separate named QtTest row.
    // The inventory comparison fails if a renderer/schema grows a new tag
    // without acquiring a corresponding contract case.
    void everyElementHasContract_data() {
        QTest::addColumn<QString>("tag");
        QTest::addColumn<QByteArray>("xml");
        QTest::addColumn<QString>("stateKey");
        QTest::addColumn<QString>("handler");
        addHyuiElementContractRows();
    }

    void everyElementHasContract() {
        QFETCH(QString, tag);
        QFETCH(QByteArray, xml);
        QFETCH(QString, stateKey);
        QFETCH(QString, handler);
        hyui::Document d;
        QVERIFY2(d.parse(xml), qPrintable(tag + ": " + d.error));
        int matches = 0;
        const std::function<void(const hyui::Node&)> visit = [&](const hyui::Node& node) {
            if (node.tag == tag) { ++matches; }
            for (const auto& child : node.children) { visit(child); }
        };
        visit(d.window);
        QCOMPARE(matches, 1);
        if (!stateKey.isEmpty()) {
            QVERIFY2(d.initialState.contains(stateKey), qPrintable(tag + ": missing state " + stateKey));
        }
        if (!handler.isEmpty()) {
            QVERIFY2(d.handlers.value(handler).contains("subject"), qPrintable(tag + ": missing callback"));
        }
        if (tag == "PasswordInput") {
            QVERIFY(d.secretInputs.contains("subject"));
            QVERIFY(!d.initialState.contains("subject.text"));
            QVERIFY(!d.initialState.contains("subject.value"));
        }
    }

    void everyElementHasInventoryCoverage() {
        const QSet<QString> expected = { "Window", "ColumnPanel", "RowPanel", "ScrollView", "GridPanel", "Panel", "SplitView", "StatusBar", "MenuBar", "Menu", "MenuItem", "ContextMenu", "Popover", "Toolbar", "ToolButton", "Clipboard", "Tabs", "Tab", "ListBox", "Table", "RadioGroup", "Image", "Dialog", "Label", "ValidationMessage", "Button", "ToggleButton", "Input", "SearchInput", "PasswordInput", "FilePicker", "TextArea", "CheckBox", "Switch", "Select", "Slider", "NumberInput", "ProgressBar", "Spinner", "Separator", "Spacer", "State", "Timer" };
        QSet<QString> actual;
        for (const QString& tag : hyui::Document::supportedElements()) { actual.insert(tag); }
        QCOMPARE(expected.size(), 43);
        QCOMPARE(actual, expected);
    }

    void dialogWithNativeMultiChoiceButtons() {
        hyui::Document d;
        QVERIFY2(d.parse(R"HYUI(<Window version="1">
            <Dialog id="choice" title="Choose" text="Select an action"
                    buttons="Open|Save|Export|Cancel" open="false" onClose="Chosen"/>
        </Window>)HYUI"), qPrintable(d.error));
        QCOMPARE(d.ranges.value("choice").first, 0);
        QCOMPARE(d.ranges.value("choice").second, 3);
        hyui::Bridge bridge(d, {}, {});
        QVERIFY(bridge.apply("HYUI\tSET\tchoice\topen\ttrue\n"
                             "HYUI\tSET\tchoice\tvalue\t3\n"));
        QCOMPARE(bridge.state().value("choice.value").toInt(), 3);
        QVERIFY(!bridge.apply("HYUI\tSET\tchoice\tvalue\t4\n"));
        QVERIFY(!d.parse(R"HYUI(<Window version="1">
            <Dialog title="Too many" buttons="1|2|3|4|5|6|7|8|9"/>
        </Window>)HYUI"));
    }

    void validatesDataAndRejectsCode() {
        hyui::Document d;
        QVERIFY(d.parse("<Window version=\"1\"><Label id=\"greeting\" text=\"Hello &amp; goodbye\" /></Window>"));
        QCOMPARE(d.initialState["greeting.text"].toString(), "Hello & goodbye");
        const QList<QByteArray> invalid = {
            "<Window version=\"2\"/>", "<Window version=\"1\"><WebView/></Window>",
            "<Window version=\"1\"><Input id=\"x\"/><Input id=\"x\"/></Window>",
            "<Window version=\"1\"><Button onClick=\"Qt.quit()\"/></Window>",
            "<Window version=\"1\"><Label text=\"hi\" onClicked=\"Run\"/></Window>",
            "<!DOCTYPE Window [<!ENTITY x 'injected'>]><Window version=\"1\"/>",
            "<Window version=\"1\"><Label><Input/></Label></Window>",
            "<Window version=\"1\"><Timer interval=\"0\" onTick=\"Tick\"/></Window>",
            "<Window version=\"1\"><Label text=\"unclosed\"></Window>",
            "<Window version=\"1\"/><Window version=\"1\"/>",
            "<Window version=\"1\"><Slider minimum=\"50\" maximum=\"10\"/></Window>",
            "<Window version=\"1\"><CheckBox checked=\"yes\"/></Window>"
        };
        for (const auto& xml : invalid) { QVERIFY2(!d.parse(xml), xml.constData()); QVERIFY(!d.error.isEmpty()); }
        QByteArray nested = "<Window version=\"1\">";
        for (int i = 0; i < 34; ++i) { nested += "<Panel>"; }
        for (int i = 0; i < 34; ++i) { nested += "</Panel>"; }
        nested += "</Window>";
        QVERIFY(!d.parse(nested));
    }

    void toggleButtonAndValidationMessageContract() {
        hyui::Document document;
        QVERIFY(document.parse(R"(<Window version="1"><ToggleButton id="flag" text="Enable" checked="true" onChange="Flip"/><ValidationMessage id="error" text="Required field" severity="warning"/></Window>)"));
        QCOMPARE(document.initialState["flag.checked"].toBool(), true);
        QCOMPARE(document.initialState["error.text"].toString(), QString("Required field"));
        QVERIFY(document.properties["flag"].contains("checked"));
        QVERIFY(document.properties["error"].contains("text"));
        QVERIFY(document.handlers["Flip"].contains("flag"));
        const QList<QByteArray> invalid = {
            R"(<Window version="1"><ToggleButton checked="yes"/></Window>)",
            R"(<Window version="1"><ValidationMessage severity="critical"/></Window>)",
            R"(<Window version="1"><ToggleButton onClick="Wrong"/></Window>)",
            R"(<Window version="1"><ValidationMessage checked="true"/></Window>)"
        };
        for (const QByteArray& xml : invalid) {
            hyui::Document malformed;
            QVERIFY2(!malformed.parse(xml), xml.constData());
        }
    }

    void splitViewAndStatusBarContract() {
        hyui::Document document;
        QVERIFY(document.parse(R"(<Window version="1"><SplitView id="split" height="240" value="260" onChange="Resize"><Panel id="left"><Label text="files"/></Panel><Panel id="right"><Label text="editor"/></Panel></SplitView><StatusBar id="status" text="Ready"/></Window>)"));
        QCOMPARE(document.window.children[0].children.size(), size_t(2));
        QCOMPARE(document.initialState["split.value"].toInt(), 260);
        QCOMPARE(document.initialState["status.text"].toString(), QString("Ready"));
        QVERIFY(document.properties["split"].contains("value"));
        QVERIFY(document.properties["status"].contains("text"));
        QVERIFY(document.handlers["Resize"].contains("split"));
        const QList<QByteArray> invalid = {
            R"(<Window version="1"><SplitView><Panel/></SplitView></Window>)",
            R"(<Window version="1"><SplitView><Panel/><Panel/><Panel/></SplitView></Window>)",
            R"(<Window version="1"><SplitView><State value="secret"/><Panel/></SplitView></Window>)",
            R"(<Window version="1"><SplitView value="50000"><Panel/><Panel/></SplitView></Window>)",
            R"(<Window version="1"><StatusBar checked="true"/></Window>)"
        };
        for (const QByteArray& xml : invalid) {
            hyui::Document malformed;
            QVERIFY2(!malformed.parse(xml), xml.constData());
        }
    }

    void responseIsTypedAndAtomic() {
        hyui::Document d;
        QVERIFY(d.parse("<Window version=\"1\"><Label id=\"status\" text=\"ready\"/><ProgressBar id=\"progress\"/><Spinner id=\"busy\"/></Window>"));
        hyui::Bridge b(d, {}, {});
        QVERIFY(b.apply("HYUI\tSET\tstatus\ttext\tHello%09world%0A%2525\nHYUI\tSET\tprogress\tvalue\t50\n"));
        QCOMPARE(b.state()["status.text"].toString(), "Hello\tworld\n%25");
        QCOMPARE(b.state()["progress.value"].toInt(), 50);
        QVERIFY(!b.apply("HYUI\tSET\tstatus\ttext\tshould not commit\nHYUI\tSET\tbusy\trunning\tyes\n"));
        QCOMPARE(b.state()["status.text"].toString(), "Hello\tworld\n%25");
        QVERIFY(!b.apply("HYUI\tSET\tmissing\ttext\tbad\n"));
        QVERIFY(!b.apply("HYUI\tSET\tprogress\tvalue\tnan\n"));
        QVERIFY(!b.apply("HYUI\tSET\tprogress\tvalue\t101\n"));
        QCOMPARE(hyui::Bridge::decode(hyui::Bridge::encode("%09\n\t\r café")), "%09\n\t\r café");
    }

    void expandedControlsValidateAndBind() {
        hyui::Document d;
        QVERIFY(d.parse(R"(<Window version="1"><MenuBar><Menu text="File"><MenuItem id="open" text="Open" shortcut="Primary+O" onClick="Open"/></Menu></MenuBar><Tabs id="tabs" value="1" onChange="Choose"><Tab title="One"><Image source="assets/logo.png" height="80"/></Tab><Tab title="Two"><ListBox id="list" items="One|Two" value="1"/><Table id="table" columns="Name|State" rows="A|Ready&#10;B|Waiting"/><RadioGroup id="radio" items="Stable|Preview"/></Tab></Tabs><Dialog id="confirm" title="Confirm" text="Continue?" buttons="Yes|No" open="false" onClose="Closed"/></Window>)"));
        QCOMPARE(d.ranges["tabs"].second, 1);
        QCOMPARE(d.ranges["list"].second, 1);
        QCOMPARE(d.ranges["table"].second, 1);
        QCOMPARE(d.ranges["radio"].second, 1);
        QCOMPARE(d.initialState["confirm.open"].toBool(), false);
        QVERIFY(d.handlers["Open"].contains("open")); QVERIFY(d.handlers["Closed"].contains("confirm"));
        const QList<QByteArray> invalid = {
            "<Window version=\"1\"><Tabs/></Window>",
            "<Window version=\"1\"><Tabs value=\"1\"><Tab/></Tabs></Window>",
            "<Window version=\"1\"><Tabs><Label/></Tabs></Window>",
            "<Window version=\"1\"><Tab/></Window>",
            "<Window version=\"1\"><MenuItem/></Window>",
            "<Window version=\"1\"><MenuBar><Button/></MenuBar></Window>",
            "<Window version=\"1\"><MenuBar><Menu text=\"File\"><MenuItem text=\"Open\" shortcut=\"Ctrl+O\" onClick=\"Open\"/></Menu></MenuBar></Window>",
            "<Window version=\"1\"><MenuBar><Menu text=\"File\"><MenuItem text=\"Open\" shortcut=\"Primary+O\"/></Menu></MenuBar></Window>",
            "<Window version=\"1\"><MenuBar><Menu text=\"File\"><MenuItem text=\"Open\" shortcut=\"Primary+O\" onClick=\"Open\"/><MenuItem text=\"Again\" shortcut=\"Primary+O\" onClick=\"Again\"/></Menu></MenuBar></Window>",
            "<Window version=\"1\"><ListBox/></Window>",
            "<Window version=\"1\"><RadioGroup items=\"One\" value=\"1\"/></Window>",
            "<Window version=\"1\"><Table columns=\"A|B\" rows=\"One\"/></Window>",
            "<Window version=\"1\"><Dialog buttons=\"1|2|3|4|5|6|7|8|9\"/></Window>",
            "<Window version=\"1\"><Image source=\"../secret.png\"/></Window>",
            "<Window version=\"1\"><Image source=\"https://example.com/image.png\"/></Window>"
        };
        for (const auto& xml : invalid) { QVERIFY2(!d.parse(xml), xml.constData()); }
    }
    void expandedResponsesAreAtomic() {
        hyui::Document d; QVERIFY(d.parse(R"(<Window version="1"><Tabs id="tabs"><Tab title="One"/><Tab title="Two"/></Tabs><Dialog id="confirm" buttons="Yes|No" open="false"/><RadioGroup id="radio" items="One|Two"/></Window>)"));
        hyui::Bridge b(d, {}, {});
        QVERIFY(b.apply("HYUI\tSET\ttabs\tvalue\t1\nHYUI\tSET\tconfirm\topen\ttrue\nHYUI\tSET\tradio\tvalue\t1\n"));
        QCOMPARE(b.state()["confirm.open"].toBool(), true);
        QVERIFY(!b.apply("HYUI\tSET\tconfirm\topen\tfalse\nHYUI\tSET\ttabs\tvalue\t2\n"));
        QCOMPARE(b.state()["confirm.open"].toBool(), true);
        QVERIFY(!b.apply("HYUI\tSET\tconfirm\topen\tyes\n"));
        QVERIFY(!b.apply("HYUI\tSET\tradio\tvalue\t2\n"));
    }

    void searchInputAndTooltipContract() {
        hyui::Document d;
        QVERIFY(d.parse(R"(<Window version="1"><SearchInput id="search" text="café" placeholder="Find" onChange="Search" onSubmit="Submit" tooltip="Search projects" accessibleName="Project search"/><Button id="go" text="Go" tooltip="Run search"/></Window>)"));
        QCOMPARE(d.initialState["search.text"].toString(), "café");
        QCOMPARE(d.window.children[0].attributes.value("tooltip"), "Search projects");
        QVERIFY(d.handlers["Search"].contains("search"));
        QVERIFY(d.handlers["Submit"].contains("search"));
        hyui::Bridge bridge(d, {}, {});
        QVERIFY(bridge.apply("HYUI\tSET\tsearch\ttext\tprojects\n"));
        QCOMPARE(bridge.state()["search.text"].toString(), "projects");
        QVERIFY(!bridge.apply("HYUI\tSET\tsearch\tvalue\t1\n"));
        QVERIFY(!d.parse("<Window version=\"1\"><SearchInput search=\"unsafe\"/></Window>"));
        QVERIFY(!d.parse("<Window version=\"1\"><SearchInput><Button/></SearchInput></Window>"));
        QVERIFY(!d.parse("<Window version=\"1\" tooltip=\"invalid\"/>"));
        QVERIFY(!d.parse("<Window version=\"1\"><Dialog tooltip=\"invalid\"/></Window>"));
        QVERIFY(!d.parse("<Window version=\"1\"><MenuBar tooltip=\"invalid\"/></Window>"));
    }

    void nativeToolbarContract() {
        hyui::Document d;
        QVERIFY(d.parse(R"(<Window version="1"><Toolbar id="commands" visible="false"><ToolButton id="open" text="Open" onClick="Open" accessibleName="Open document"/><ToolButton id="save" text="Save" onClick="Save"/></Toolbar></Window>)"));
        QCOMPARE(d.window.children[0].children.size(), size_t(2));
        QCOMPARE(d.initialState["commands.visible"].toBool(), false);
        QVERIFY(d.handlers["Open"].contains("open"));
        hyui::Bridge bridge(d, {}, {});
        QVERIFY(bridge.apply("HYUI\tSET\tcommands\tvisible\ttrue\nHYUI\tSET\topen\ttext\tOpen file\nHYUI\tSET\tsave\tenabled\tfalse\n"));
        QCOMPARE(bridge.state()["open.text"].toString(), "Open file");
        QCOMPARE(bridge.state()["save.enabled"].toBool(), false);
        QVERIFY(bridge.apply("HYUI\tSET\tcommands\tenabled\tfalse\n"));
        QCOMPARE(bridge.state()["commands.enabled"].toBool(), false);
        const QList<QByteArray> invalid = {
            "<Window version=\"1\"><Toolbar/></Window>",
            "<Window version=\"1\"><ToolButton text=\"Open\" onClick=\"Open\"/></Window>",
            "<Window version=\"1\"><Panel><Toolbar><ToolButton text=\"Open\" onClick=\"Open\"/></Toolbar></Panel></Window>",
            "<Window version=\"1\"><Toolbar><Button text=\"Bad\"/></Toolbar></Window>",
            "<Window version=\"1\"><Toolbar><ToolButton text=\"Open\"/></Toolbar></Window>",
            "<Window version=\"1\"><Toolbar><ToolButton onClick=\"Open\"/></Toolbar></Window>",
            "<Window version=\"1\"><Toolbar><ToolButton text=\"Open\" onClick=\"Open\"/></Toolbar><Toolbar><ToolButton text=\"Again\" onClick=\"Again\"/></Toolbar></Window>",
            "<Window version=\"1\"><Toolbar tooltip=\"ignored\"><ToolButton text=\"Open\" onClick=\"Open\"/></Toolbar></Window>",
            "<Window version=\"1\"><Toolbar><ToolButton text=\"Open\" onClick=\"Open\" preferredWidth=\"100\"/></Toolbar></Window>"
        };
        for (const auto& xml : invalid) { QVERIFY2(!d.parse(xml), xml.constData()); }
    }

    void anchoredPopoverContract() {
        hyui::Document d;
        QVERIFY(d.parse(R"(<Window version="1"><Button id="anchor" text="Tip" onClick="Tip"/><Popover id="tip" target="anchor" text="Help text" open="false" onClose="Closed"/></Window>)"));
        QCOMPARE(d.initialState["tip.open"].toBool(), false);
        QCOMPARE(d.initialState["tip.text"].toString(), "Help text");
        QVERIFY(d.handlers["Closed"].contains("tip"));
        hyui::Bridge bridge(d, {}, {});
        QVERIFY(bridge.apply("HYUI\tSET\ttip\ttext\tUpdated tip\nHYUI\tSET\ttip\topen\ttrue\n"));
        QCOMPARE(bridge.state()["tip.text"].toString(), "Updated tip");
        QCOMPARE(bridge.state()["tip.open"].toBool(), true);
        QVERIFY(!bridge.apply("HYUI\tSET\ttip\tvisible\tfalse\n"));
        // A native Popover may now contain interactive Hydrogen controls.
        QVERIFY(d.parse(R"(<Window version="1"><Button id="anchor" text="Tip"/>
            <Popover id="tip" target="anchor" text="Help">
                <Button id="inspect" text="Inspect" onClick="Inspect"/>
            </Popover></Window>)"));
        QCOMPARE(d.window.children.back().children.size(),size_t(1));
        QVERIFY(d.handlers["Inspect"].contains("inspect"));
        const QList<QByteArray> invalid = {
            "<Window version=\"1\"><Popover id=\"tip\" target=\"missing\" text=\"Help\"/></Window>",
            "<Window version=\"1\"><Label id=\"anchor\" text=\"Help\"/><Popover id=\"tip\" target=\"anchor\" text=\"Help\"/></Window>",
            "<Window version=\"1\"><Button id=\"anchor\"/><Popover target=\"anchor\" text=\"Help\"/></Window>",
            "<Window version=\"1\"><Button id=\"anchor\"/><Popover id=\"tip\" target=\"anchor\"/></Window>",
            "<Window version=\"1\"><Button id=\"anchor\"/><Popover id=\"tip\" target=\"anchor\" text=\"Help\" visible=\"true\"/></Window>",
            "<Window version=\"1\"><Panel><Popover id=\"tip\" target=\"anchor\" text=\"Help\"/></Panel></Window>"
        };
        for (const auto& xml : invalid) { QVERIFY2(!d.parse(xml), xml.constData()); }
    }

    void scrollViewContract() {
        hyui::Document d;
        QVERIFY(d.parse(R"(<Window version="1"><ScrollView id="details" height="90" gap="6" enabled="false" tooltip="Scroll details"><Label text="First"/><Button id="action" text="Run" onClick="Run"/></ScrollView></Window>)"));
        QCOMPARE(d.window.children[0].children.size(), size_t(2));
        QCOMPARE(d.window.children[0].attributes.value("height"), "90");
        QCOMPARE(d.initialState["details.enabled"].toBool(), false);
        QVERIFY(d.handlers["Run"].contains("action"));
        hyui::Bridge bridge(d, {}, {});
        QVERIFY(bridge.apply("HYUI\tSET\tdetails\tvisible\tfalse\nHYUI\tSET\tdetails\tenabled\ttrue\n"));
        QCOMPARE(bridge.state()["details.visible"].toBool(), false);
        QCOMPARE(bridge.state()["details.enabled"].toBool(), true);
        QVERIFY(!d.parse("<Window version=\"1\"><ScrollView height=\"0\"/></Window>"));
        QVERIFY(!d.parse("<Window version=\"1\"><ScrollView gap=\"-1\"/></Window>"));
        QVERIFY(!d.parse("<Window version=\"1\"><ScrollView onScroll=\"Bad\"/></Window>"));
    }

    void passwordInputUsesPrivateEventTransport() {
        hyui::Document d;
        QVERIFY(d.parse(R"(<Window version="1"><PasswordInput id="password" placeholder="Private code" onSubmit="Password" accessibleName="Private code"/><Label id="status" text="ready"/><Button id="go" onClick="CheckSecretSnapshot"/></Window>)"));
        QVERIFY(d.secretInputs.contains("password"));
        QVERIFY(!d.initialState.contains("password.text"));
        QVERIFY(!d.properties["password"].contains("text"));
        QVERIFY(!d.parse("<Window version=\"1\"><PasswordInput text=\"embedded secret\"/></Window>"));
        QVERIFY(!d.parse("<Window version=\"1\"><PasswordInput value=\"1\"/></Window>"));
        QVERIFY(!d.parse("<Window version=\"1\"><PasswordInput><Label/></PasswordInput></Window>"));
        QVERIFY(d.parse(R"(<Window version="1"><PasswordInput id="password" onSubmit="Password"/><Label id="status" text="ready"/><Button id="go" onClick="CheckSecretSnapshot"/></Window>)"));
        hyui::Bridge bridge(d, QCoreApplication::applicationFilePath(), QDir::currentPath());
        bridge.storeSecret("password", "gallery-pass");
        bridge.store("password", "text", "must not persist");
        QVERIFY(!bridge.state().contains("password.text"));
        bridge.dispatch("CheckSecretSnapshot", "go");
        QTRY_VERIFY_WITH_TIMEOUT(!bridge.busy(), 5000);
        QCOMPARE(bridge.state()["status.text"].toString(), "no-secret");
        bridge.dispatch("Password", "password");
        QTRY_VERIFY_WITH_TIMEOUT(!bridge.busy(), 5000);
        QCOMPARE(bridge.error(), QString());
        QCOMPARE(bridge.state()["status.text"].toString(), "accepted");
        QVERIFY(!bridge.apply("HYUI\tSET\tpassword\ttext\tbad\n"));
    }
    void filePickerContractAndPathTransport() {
        hyui::Document d;
        QVERIFY(d.parse(R"(<Window version="1"><FilePicker id="choose" mode="open" text="Open document" onPick="Pick" onCancel="Cancel" accessibleName="Open document"/><FilePicker id="save" mode="save" text="Save document" onPick="Save"/><FilePicker id="folder" mode="folder" text="Choose folder" onPick="Folder"/><Label id="status" text="ready"/></Window>)"));
        QCOMPARE(d.initialState["choose.path"].toString(), "");
        QVERIFY(d.properties["choose"].contains("path"));
        QVERIFY(d.handlers["Pick"].contains("choose"));
        QVERIFY(d.handlers["Cancel"].contains("choose"));
        for (const QByteArray xml : {
                 QByteArray("<Window version=\"1\"><FilePicker mode=\"open\" text=\"Open\"/></Window>"),
                 QByteArray("<Window version=\"1\"><FilePicker mode=\"network\" text=\"Open\" onPick=\"Pick\"/></Window>"),
                 QByteArray("<Window version=\"1\"><FilePicker mode=\"save\" text=\"\" onPick=\"Pick\"/></Window>"),
                 QByteArray("<Window version=\"1\"><FilePicker mode=\"folder\" text=\"Folder\" path=\"/etc\" onPick=\"Pick\"/></Window>"),
                 QByteArray("<Window version=\"1\"><FilePicker mode=\"open\" text=\"Open\" onPick=\"Pick\"><Input/></FilePicker></Window>")
             }) { QVERIFY2(!d.parse(xml), xml.constData()); }
        QVERIFY(d.parse(R"(<Window version="1"><FilePicker id="choose" mode="open" text="Open document" onPick="Pick"/><Label id="status" text="ready"/></Window>)"));
        hyui::Bridge bridge(d, QCoreApplication::applicationFilePath(), QDir::currentPath());
        const QString path = "/tmp/Aurora O'Brien/café.txt";
        bridge.store("choose", "path", path);
        bridge.dispatch("Pick", "choose");
        QTRY_VERIFY_WITH_TIMEOUT(!bridge.busy(), 5000);
        QCOMPARE(bridge.error(), QString());
        QCOMPARE(bridge.state()["status.text"].toString().normalized(QString::NormalizationForm_C), path.normalized(QString::NormalizationForm_C));
    }
    void contextMenuContract() {
        hyui::Document d;
        QVERIFY(d.parse(R"(<Window version="1"><ListBox id="items" items="One|Two"/><ContextMenu target="items"><MenuItem id="inspect" text="Inspect" onClick="Inspect"/></ContextMenu></Window>)"));
        QVERIFY(d.handlers["Inspect"].contains("inspect"));
        QVERIFY(d.properties[d.window.children[1].id].isEmpty());
        for (const QByteArray xml : {
                 QByteArray(R"(<Window version="1"><ContextMenu target="missing"><MenuItem text="Inspect" onClick="Inspect"/></ContextMenu></Window>)"),
                 QByteArray(R"(<Window version="1"><Button id="target"/><ContextMenu target="target"/></Window>)"),
                 QByteArray(R"(<Window version="1"><Button id="target"/><ContextMenu target="target"><Button text="Bad"/></ContextMenu></Window>)"),
                 QByteArray(R"(<Window version="1"><Button id="target"/><ContextMenu target="target"><MenuItem text="One"/></ContextMenu><ContextMenu target="target"><MenuItem text="Two"/></ContextMenu></Window>)"),
                 QByteArray(R"(<Window version="1"><Button id="target"/><ContextMenu target="target" visible="false"><MenuItem text="Bad"/></ContextMenu></Window>)"),
                 QByteArray(R"(<Window version="1"><Button id="target"/><ContextMenu target="target"><MenuItem text="Bad" shortcut="Primary+B" onClick="Bad"/></ContextMenu></Window>)")
             }) { QVERIFY2(!d.parse(xml), xml.constData()); }
    }
    void clipboardContractAndTransport() {
        hyui::Document d;
        QVERIFY(d.parse(R"(<Window version="1"><Clipboard id="clipboard" onRead="Read"/><Label id="status" text="ready"/></Window>)"));
        QCOMPARE(d.initialState["clipboard.value"].toString(), "");
        QVERIFY(d.clipboardIds.contains("clipboard"));
        QVERIFY(d.handlers["Read"].contains("clipboard"));
        for (const QByteArray xml : {
                 QByteArray(R"(<Window version="1"><Clipboard onRead="Read"/></Window>)"),
                 QByteArray(R"(<Window version="1"><Clipboard id="clipboard"/></Window>)"),
                 QByteArray(R"(<Window version="1"><Clipboard id="clipboard" onRead="Read" visible="true"/></Window>)"),
                 QByteArray(R"(<Window version="1"><Panel><Clipboard id="clipboard" onRead="Read"/></Panel></Window>)")
             }) { QVERIFY2(!d.parse(xml), xml.constData()); }
        QVERIFY(d.parse(R"(<Window version="1"><Clipboard id="clipboard" onRead="Read"/></Window>)"));
        hyui::Bridge bridge(d, QCoreApplication::applicationFilePath(), QDir::currentPath());
        QSignalSpy requested(&bridge, &hyui::Bridge::clipboardRequested);
        QVERIFY(bridge.apply(QString("HYUI\tCLIPBOARD\tWRITE\tclipboard\tcafé%09note\n").toUtf8()));
        QCOMPARE(bridge.state()["clipboard.value"].toString(), "café\tnote");
        QCOMPARE(requested.size(), 1);
        QCOMPARE(requested[0][1].toString(), "WRITE");
        QVERIFY(bridge.apply("HYUI\tCLIPBOARD\tREAD\tclipboard\n"));
        QCOMPARE(requested.size(), 2);
        QCOMPARE(requested[1][1].toString(), "READ");
        QVERIFY(bridge.storeClipboardText("clipboard", "café\tline\nnext"));
        QCOMPARE(bridge.state()["clipboard.value"].toString(), "café\tline\nnext");
        QVERIFY(!bridge.apply("HYUI\tCLIPBOARD\tWRITE\tmissing\tx\n"));
        QVERIFY(!bridge.apply("HYUI\tCLIPBOARD\tREAD\tclipboard\textra\n"));
        QVERIFY(!bridge.storeClipboardText("clipboard", QString(16385, 'x')));
        QCOMPARE(requested.size(), 2);
        hyui::Document privacy;
        QVERIFY(privacy.parse(R"(<Window version="1"><Clipboard id="clipboard" onRead="Read"/><Button id="probe" onClick="Probe"/><Label id="status" text="ready"/></Window>)"));
        hyui::Bridge eventBridge(privacy, QCoreApplication::applicationFilePath(), QDir::currentPath());
        QVERIFY(eventBridge.storeClipboardText("clipboard", "café private"));
        eventBridge.dispatch("Probe", "probe");
        QTRY_VERIFY_WITH_TIMEOUT(!eventBridge.busy(), 5000);
        QCOMPARE(eventBridge.state()["status.text"].toString(), "private");
        eventBridge.dispatch("Read", "clipboard");
        QTRY_VERIFY_WITH_TIMEOUT(!eventBridge.busy(), 5000);
        QCOMPARE(eventBridge.state()["status.text"].toString().normalized(QString::NormalizationForm_C), QString("café private"));
    }

    void callbacksUseArgumentVectors() {
        hyui::Document d;
        QVERIFY(d.parse("<Window version=\"1\"><Input id=\"name\"/><Label id=\"status\"/><Button id=\"go\" onClick=\"Submit\"/></Window>"));
        hyui::Bridge b(d, QCoreApplication::applicationFilePath(), QDir::currentPath());
        const QString input = "O'Brien \"quoted\"; $(touch /tmp/hyui-must-not-exist)\nRésumé";
        b.store("name", "text", input);
        b.dispatch("Submit", "go");
        QTRY_VERIFY_WITH_TIMEOUT(!b.busy(), 5000);
        QCOMPARE(b.error(), QString());
        // Cocoa may canonically decompose argv. Preserve text and shell
        // metacharacters while allowing equivalent Unicode representations.
        QCOMPARE(b.state()["status.text"].toString().normalized(QString::NormalizationForm_C), input.normalized(QString::NormalizationForm_C));
        b.dispatch("Unregistered", "go");
        QVERIFY(!b.error().isEmpty());
    }


};

int main(int argc, char** argv) {
    // A real child-process backend, also used to verify shell-free Unicode input.
    if (argc >= 4 && QByteArray(argv[1]) == "--hyui-event") {
        if (QByteArray(argv[2]) == "Password" || QByteArray(argv[2]) == "CheckSecretSnapshot") {
            QString result = "no-secret";
            for (int i = 4; i + 1 < argc; i += 2) {
                if (QByteArray(argv[i + 1]) == "gallery-pass") { result = "leaked-argument"; }
                if (QByteArray(argv[i]) == "--hyui-secret:password") {
                    QFile file(QString::fromUtf8(argv[i + 1]));
                    result = file.open(QIODevice::ReadOnly) && file.readAll() == "gallery-pass" ? "accepted" : "rejected";
                }
            }
            std::cout << "HYUI\tSET\tstatus\ttext\t" << result.toStdString() << '\n';
            return 0;
        }
        if (QByteArray(argv[2]) == "Pick") {
            QString path;
            for (int i = 4; i + 1 < argc; i += 2) {
                if (QByteArray(argv[i]) == "choose") { path = QString::fromUtf8(argv[i + 1]); }
            }
            std::cout << "HYUI\tSET\tstatus\ttext\t" << hyui::Bridge::encode(path).toStdString() << '\n';
            return 0;
        }
        if (QByteArray(argv[2]) == "Probe" || QByteArray(argv[2]) == "Read") {
            QString value = "private";
            for (int i = 4; i + 1 < argc; i += 2) {
                if (QByteArray(argv[i]) == "clipboard") { value = QByteArray(argv[2]) == "Read" ? QString::fromUtf8(argv[i + 1]) : "leaked"; }
            }
            std::cout << "HYUI\tSET\tstatus\ttext\t" << hyui::Bridge::encode(value).toStdString() << '\n';
            return 0;
        }
        QString value;
        for (int i = 4; i + 1 < argc; i += 2) {
            if (QByteArray(argv[i]) == "name") { value = QString::fromUtf8(argv[i + 1]); }
        }
        std::cout << "HYUI\tSET\tstatus\ttext\t" << hyui::Bridge::encode(value).toStdString() << '\n';
        return 0;
    }
    QCoreApplication app(argc, argv);
    HyuiTests tests;
    return QTest::qExec(&tests, argc, argv);
}
#include "tests.moc"
