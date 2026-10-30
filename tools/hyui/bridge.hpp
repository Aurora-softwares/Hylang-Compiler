#pragma once

#include "document.hpp"
#include <QObject>
#include <QProcess>
#include <QQueue>
#include <QTimer>

namespace hyui {
class Bridge : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap state READ state NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
public:
    Bridge(const Document& document, QString backend, QString directory, QObject* parent = nullptr);
    QVariantMap state() const { return values; }
    QString error() const { return lastError; }
    bool busy() const { return active; }
    Q_INVOKABLE void store(const QString& id, const QString& property, const QVariant& value);
    Q_INVOKABLE void dispatch(const QString& handler, const QString& sender);
    Q_INVOKABLE bool isApplying() const { return applying; }
    bool apply(const QByteArray& response);
    static QString decode(QString value);
    static QString encode(QString value);
signals:
    void changed();
    void errorChanged();
    void busyChanged();
    void idle();
private:
    void next();
    void fail(const QString& message);
    const Document& document;
    QVariantMap values;
    QString backend, directory, lastError;
    QProcess process;
    QTimer timeout;
    QByteArray output, errors;
    QQueue<QPair<QString, QString>> pending;
    bool active = false;
    bool overflow = false;
    bool applying = false;
};
}
