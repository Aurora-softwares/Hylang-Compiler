#include "bridge.hpp"
#include "document.hpp"
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickWindow>
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

    void rendersAndReflows() {
        hyui::Document d;
        QVERIFY(d.parse(R"(<Window version="1"><RowPanel id="row" breakpoint="700">
          <Panel id="left" title="Settings"><Input id="entry" text="a &quot;quoted&quot; value"/>
          <Button text="Click"/><CheckBox/><Switch/><Select items="one|two"/>
          <Slider/><NumberInput/><TextArea id="notes" text="Initial" onChange="Changed"/><ProgressBar/><Spinner running="false"/>
          </Panel><Panel id="right"><Label text="Long text wraps instead of overflowing the available screen width."/></Panel>
          </RowPanel></Window>)"));
        hyui::Bridge bridge(d, {}, {});
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("bridge", &bridge);
        engine.loadData(d.qml().toUtf8());
        QVERIFY(!engine.rootObjects().isEmpty());
        auto* window = qobject_cast<QQuickWindow*>(engine.rootObjects().first());
        QVERIFY(window);
        QSignalSpy backendStarted(&bridge, &hyui::Bridge::busyChanged);
        QVERIFY(bridge.apply("HYUI\tSET\tnotes\ttext\tUpdated by Hydrogen\n"));
        QCOMPARE(backendStarted.count(), 0);
        QVERIFY(!bridge.busy());
        auto* row = window->findChild<QQuickItem*>("row");
        auto* left = window->findChild<QQuickItem*>("left");
        auto* right = window->findChild<QQuickItem*>("right");
        QVERIFY(row && left && right);
        window->resize(1100, 800); window->show();
        QTRY_COMPARE(row->property("columns").toInt(), 2);
        QTRY_VERIFY(right->x() > left->x());
        window->resize(360, 640);
        QTRY_COMPARE(row->property("columns").toInt(), 1);
        QTRY_VERIFY(right->y() > left->y());
        QVERIFY(left->width() > 0 && left->width() < 360);
        QVERIFY(right->width() > 0 && right->width() < 360);
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
    QGuiApplication app(argc, argv);
    HyuiTests tests;
    return QTest::qExec(&tests, argc, argv);
}
#include "tests.moc"
