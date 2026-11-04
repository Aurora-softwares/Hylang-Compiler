#pragma once

#include <QMap>
#include <QSet>
#include <QString>
#include <QStringList>
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
    static QStringList supportedElements();
    QString resourcePath(const QString& relative) const;
    QString error;
    QString sourcePath;
    Node window;
    QVariantMap initialState;
    QMap<QString, QSet<QString>> properties;
    QMap<QString, QSet<QString>> handlers;
    QSet<QString> secretInputs;
    QSet<QString> clipboardIds;
    QMap<QString, QPair<int, int>> ranges;
};
}
