#include "bridge.hpp"
#include "document.hpp"
#include <QCoreApplication>
#include <QtTest>
#include <iostream>

class HyuiTests : public QObject {
    Q_OBJECT
private slots:
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
        QVERIFY(d.parse(R"(<Window version="1"><MenuBar><Menu text="File"><MenuItem id="open" text="Open" onClick="Open"/></Menu></MenuBar><Tabs id="tabs" value="1" onChange="Choose"><Tab title="One"><Image source="assets/logo.png" height="80"/></Tab><Tab title="Two"><ListBox id="list" items="One|Two" value="1"/><Table id="table" columns="Name|State" rows="A|Ready&#10;B|Waiting"/><RadioGroup id="radio" items="Stable|Preview"/></Tab></Tabs><Dialog id="confirm" title="Confirm" text="Continue?" buttons="Yes|No" open="false" onClose="Closed"/></Window>)"));
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
            "<Window version=\"1\"><ListBox/></Window>",
            "<Window version=\"1\"><RadioGroup items=\"One\" value=\"1\"/></Window>",
            "<Window version=\"1\"><Table columns=\"A|B\" rows=\"One\"/></Window>",
            "<Window version=\"1\"><Dialog buttons=\"1|2|3|4\"/></Window>",
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

    void callbacksUseArgumentVectors() {
        hyui::Document d;
        QVERIFY(d.parse("<Window version=\"1\"><Input id=\"name\"/><Label id=\"status\"/><Button id=\"go\" onClick=\"Submit\"/></Window>"));
        hyui::Bridge b(d, QCoreApplication::applicationFilePath(), QDir::currentPath());
        const QString input = "O'Brien \"quoted\"; $(touch /tmp/hyui-must-not-exist)\nRésumé";
        b.store("name", "text", input);
        b.dispatch("Submit", "go");
        QTRY_VERIFY_WITH_TIMEOUT(!b.busy(), 5000);
        QCOMPARE(b.error(), QString());
        QCOMPARE(b.state()["status.text"].toString(), input);
        b.dispatch("Unregistered", "go");
        QVERIFY(!b.error().isEmpty());
    }


};

int main(int argc, char** argv) {
    // A real child-process backend, also used to verify shell-free Unicode input.
    if (argc >= 4 && QByteArray(argv[1]) == "--hyui-event") {
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
