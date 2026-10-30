#pragma once

#include <QMap>
#include <QSet>
#include <QString>
#include <QVariantMap>
#include <vector>

namespace hyui {
struct Node {
    QString tag;
    QMap<QString, QString> attributes;
    std::vector<Node> children;
    QString id;
};

// HYUI v1 is data, never executable QML or JavaScript.
class Document {
public:
    bool parse(const QByteArray& xml);
    QString qml() const;
    QString error;
    Node window;
    QVariantMap initialState;
    QMap<QString, QSet<QString>> properties;
    QMap<QString, QSet<QString>> handlers;
    QMap<QString, QPair<int, int>> ranges;
private:
    QString emitNode(const Node& node, int depth) const;
};
QString quote(const QString& value);
}
