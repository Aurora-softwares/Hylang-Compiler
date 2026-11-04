#pragma once
// Each row is a separate named QtTest case; keep heavyweight XML raw
// strings outside the Q_OBJECT translation unit for reliable AUTOMOC.
#include <QtTest>
inline void addHyuiElementContractRows() {
        QTest::newRow("Window") << QStringLiteral("Window")
            << QByteArray(R"HYUI(<Window version="1" id="subject"/>)HYUI")
            << QStringLiteral("") << QStringLiteral("");
        QTest::newRow("ColumnPanel") << QStringLiteral("ColumnPanel")
            << QByteArray(R"HYUI(<Window version="1"><ColumnPanel id="subject" gap="8"><Label text="Inside"/></ColumnPanel></Window>)HYUI")
            << QStringLiteral("subject.visible") << QStringLiteral("");
        QTest::newRow("RowPanel") << QStringLiteral("RowPanel")
            << QByteArray(R"HYUI(<Window version="1"><RowPanel id="subject" gap="8" breakpoint="500"><Label text="Inside"/></RowPanel></Window>)HYUI")
            << QStringLiteral("subject.visible") << QStringLiteral("");
        QTest::newRow("ScrollView") << QStringLiteral("ScrollView")
            << QByteArray(R"HYUI(<Window version="1"><ScrollView id="subject" height="150"><Label text="Inside"/></ScrollView></Window>)HYUI")
            << QStringLiteral("subject.visible") << QStringLiteral("");
        QTest::newRow("GridPanel") << QStringLiteral("GridPanel")
            << QByteArray(R"HYUI(<Window version="1"><GridPanel id="subject" columns="2" minItemWidth="100"><Label text="Inside"/></GridPanel></Window>)HYUI")
            << QStringLiteral("subject.visible") << QStringLiteral("");
        QTest::newRow("Panel") << QStringLiteral("Panel")
            << QByteArray(R"HYUI(<Window version="1"><Panel id="subject" title="Settings"><Label text="Inside"/></Panel></Window>)HYUI")
            << QStringLiteral("subject.visible") << QStringLiteral("");
        QTest::newRow("MenuBar") << QStringLiteral("MenuBar")
            << QByteArray(R"HYUI(<Window version="1"><MenuBar id="subject"><Menu text="File"><MenuItem text="Save" onClick="Save"/></Menu></MenuBar></Window>)HYUI")
            << QStringLiteral("subject.visible") << QStringLiteral("");
        QTest::newRow("Menu") << QStringLiteral("Menu")
            << QByteArray(R"HYUI(<Window version="1"><MenuBar><Menu id="subject" text="File"><MenuItem text="Save" onClick="Save"/></Menu></MenuBar></Window>)HYUI")
            << QStringLiteral("subject.visible") << QStringLiteral("");
        QTest::newRow("MenuItem") << QStringLiteral("MenuItem")
            << QByteArray(R"HYUI(<Window version="1"><MenuBar><Menu text="File"><MenuItem id="subject" text="Save" checked="true" shortcut="Primary+S" onClick="Touched"/></Menu></MenuBar></Window>)HYUI")
            << QStringLiteral("subject.checked") << QStringLiteral("Touched");
        QTest::newRow("ContextMenu") << QStringLiteral("ContextMenu")
            << QByteArray(R"HYUI(<Window version="1"><Button id="anchor" text="Anchor"/><ContextMenu id="subject" target="anchor"><MenuItem text="Inspect" onClick="Inspect"/></ContextMenu></Window>)HYUI")
            << QStringLiteral("") << QStringLiteral("");
        QTest::newRow("Popover") << QStringLiteral("Popover")
            << QByteArray(R"HYUI(<Window version="1"><Button id="anchor" text="Anchor"/><Popover id="subject" target="anchor" text="Details" open="false" onClose="Touched"><Button id="innerAction" text="Action" onClick="Inspect"/></Popover></Window>)HYUI")
            << QStringLiteral("subject.open") << QStringLiteral("Touched");
        QTest::newRow("Toolbar") << QStringLiteral("Toolbar")
            << QByteArray(R"HYUI(<Window version="1"><Toolbar id="subject"><ToolButton text="Open" onClick="Open"/></Toolbar></Window>)HYUI")
            << QStringLiteral("subject.visible") << QStringLiteral("");
        QTest::newRow("ToolButton") << QStringLiteral("ToolButton")
            << QByteArray(R"HYUI(<Window version="1"><Toolbar><ToolButton id="subject" text="Open" onClick="Touched"/></Toolbar></Window>)HYUI")
            << QStringLiteral("subject.visible") << QStringLiteral("Touched");
        QTest::newRow("Clipboard") << QStringLiteral("Clipboard")
            << QByteArray(R"HYUI(<Window version="1"><Clipboard id="subject" onRead="Touched"/></Window>)HYUI")
            << QStringLiteral("subject.value") << QStringLiteral("Touched");
        QTest::newRow("Tabs") << QStringLiteral("Tabs")
            << QByteArray(R"HYUI(<Window version="1"><Tabs id="subject" value="0" onChange="Touched"><Tab title="One"><Label text="Page"/></Tab></Tabs></Window>)HYUI")
            << QStringLiteral("subject.value") << QStringLiteral("Touched");
        QTest::newRow("Tab") << QStringLiteral("Tab")
            << QByteArray(R"HYUI(<Window version="1"><Tabs><Tab id="subject" title="One"><Label text="Page"/></Tab></Tabs></Window>)HYUI")
            << QStringLiteral("subject.visible") << QStringLiteral("");
        QTest::newRow("ListBox") << QStringLiteral("ListBox")
            << QByteArray(R"HYUI(<Window version="1"><ListBox id="subject" items="One|Two" value="1" onChange="Touched"/></Window>)HYUI")
            << QStringLiteral("subject.value") << QStringLiteral("Touched");
        QTest::newRow("Table") << QStringLiteral("Table")
            << QByteArray(R"HYUI(<Window version="1"><Table id="subject" columns="Title|Status" rows="A|Ready&#10;B|Waiting" value="1" onChange="Touched"/></Window>)HYUI")
            << QStringLiteral("subject.value") << QStringLiteral("Touched");
        QTest::newRow("RadioGroup") << QStringLiteral("RadioGroup")
            << QByteArray(R"HYUI(<Window version="1"><RadioGroup id="subject" items="One|Two" value="1" onChange="Touched"/></Window>)HYUI")
            << QStringLiteral("subject.value") << QStringLiteral("Touched");
        QTest::newRow("Image") << QStringLiteral("Image")
            << QByteArray(R"HYUI(<Window version="1"><Image id="subject" source="assets/icon.png" height="72"/></Window>)HYUI")
            << QStringLiteral("subject.visible") << QStringLiteral("");
        QTest::newRow("Dialog") << QStringLiteral("Dialog")
            << QByteArray(R"HYUI(<Window version="1"><Dialog id="subject" title="Confirm" text="Continue?" buttons="Yes|No" open="false" onClose="Touched"/></Window>)HYUI")
            << QStringLiteral("subject.open") << QStringLiteral("Touched");
        QTest::newRow("Label") << QStringLiteral("Label")
            << QByteArray(R"HYUI(<Window version="1"><Label id="subject" text="Hello" role="heading"/></Window>)HYUI")
            << QStringLiteral("subject.text") << QStringLiteral("");
        QTest::newRow("Button") << QStringLiteral("Button")
            << QByteArray(R"HYUI(<Window version="1"><Button id="subject" text="Save" primary="true" onClick="Touched"/></Window>)HYUI")
            << QStringLiteral("subject.text") << QStringLiteral("Touched");
        QTest::newRow("Input") << QStringLiteral("Input")
            << QByteArray(R"HYUI(<Window version="1"><Input id="subject" text="Draft" onChange="Touched" onSubmit="Submit"/></Window>)HYUI")
            << QStringLiteral("subject.text") << QStringLiteral("Touched");
        QTest::newRow("SearchInput") << QStringLiteral("SearchInput")
            << QByteArray(R"HYUI(<Window version="1"><SearchInput id="subject" text="Find" onChange="Touched" onSubmit="Submit"/></Window>)HYUI")
            << QStringLiteral("subject.text") << QStringLiteral("Touched");
        QTest::newRow("PasswordInput") << QStringLiteral("PasswordInput")
            << QByteArray(R"HYUI(<Window version="1"><PasswordInput id="subject" placeholder="Secret" onChange="Touched"/></Window>)HYUI")
            << QStringLiteral("subject.visible") << QStringLiteral("Touched");
        QTest::newRow("FilePicker") << QStringLiteral("FilePicker")
            << QByteArray(R"HYUI(<Window version="1"><FilePicker id="subject" mode="open" text="Open" onPick="Touched" onCancel="Cancelled"/></Window>)HYUI")
            << QStringLiteral("subject.path") << QStringLiteral("Touched");
        QTest::newRow("TextArea") << QStringLiteral("TextArea")
            << QByteArray(R"HYUI(<Window version="1"><TextArea id="subject" text="Notes" height="100" onChange="Touched"/></Window>)HYUI")
            << QStringLiteral("subject.text") << QStringLiteral("Touched");
        QTest::newRow("CheckBox") << QStringLiteral("CheckBox")
            << QByteArray(R"HYUI(<Window version="1"><CheckBox id="subject" text="Enable" checked="true" onChange="Touched"/></Window>)HYUI")
            << QStringLiteral("subject.checked") << QStringLiteral("Touched");
        QTest::newRow("Switch") << QStringLiteral("Switch")
            << QByteArray(R"HYUI(<Window version="1"><Switch id="subject" text="Enable" checked="true" onChange="Touched"/></Window>)HYUI")
            << QStringLiteral("subject.checked") << QStringLiteral("Touched");
        QTest::newRow("Select") << QStringLiteral("Select")
            << QByteArray(R"HYUI(<Window version="1"><Select id="subject" items="A|B" value="1" onChange="Touched"/></Window>)HYUI")
            << QStringLiteral("subject.value") << QStringLiteral("Touched");
        QTest::newRow("Slider") << QStringLiteral("Slider")
            << QByteArray(R"HYUI(<Window version="1"><Slider id="subject" minimum="20" maximum="80" value="35" onChange="Touched"/></Window>)HYUI")
            << QStringLiteral("subject.value") << QStringLiteral("Touched");
        QTest::newRow("NumberInput") << QStringLiteral("NumberInput")
            << QByteArray(R"HYUI(<Window version="1"><NumberInput id="subject" minimum="20" maximum="80" value="35" onChange="Touched"/></Window>)HYUI")
            << QStringLiteral("subject.value") << QStringLiteral("Touched");
        QTest::newRow("ProgressBar") << QStringLiteral("ProgressBar")
            << QByteArray(R"HYUI(<Window version="1"><ProgressBar id="subject" minimum="20" maximum="80" value="35" indeterminate="false"/></Window>)HYUI")
            << QStringLiteral("subject.value") << QStringLiteral("");
        QTest::newRow("Spinner") << QStringLiteral("Spinner")
            << QByteArray(R"HYUI(<Window version="1"><Spinner id="subject" running="true"/></Window>)HYUI")
            << QStringLiteral("subject.running") << QStringLiteral("");
        QTest::newRow("Separator") << QStringLiteral("Separator")
            << QByteArray(R"HYUI(<Window version="1"><Separator id="subject"/></Window>)HYUI")
            << QStringLiteral("subject.visible") << QStringLiteral("");
        QTest::newRow("Spacer") << QStringLiteral("Spacer")
            << QByteArray(R"HYUI(<Window version="1"><Spacer id="subject" height="12" visible="false"/></Window>)HYUI")
            << QStringLiteral("subject.visible") << QStringLiteral("");
        QTest::newRow("State") << QStringLiteral("State")
            << QByteArray(R"HYUI(<Window version="1"><State id="subject" value="draft"/></Window>)HYUI")
            << QStringLiteral("subject.value") << QStringLiteral("");
        QTest::newRow("Timer") << QStringLiteral("Timer")
            << QByteArray(R"HYUI(<Window version="1"><Timer id="subject" interval="150" running="true" onTick="Touched"/></Window>)HYUI")
            << QStringLiteral("subject.running") << QStringLiteral("Touched");
}
