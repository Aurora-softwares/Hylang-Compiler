#pragma once

#include <QMap>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QVector>
#include <vector>

namespace hyui {
struct Node {
    QString tag;
    QMap<QString, QString> attributes;
    std::vector<Node> children;
    QString id;
};

// TreeView items are preorder rows: depth:label|depth:label.
struct TreeEntry {
    QString label;
    int depth = 0;
    int parent = -1;
    QVector<int> children;
};
bool parseTreeItems(const QString& items, QVector<TreeEntry>& entries);

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
    QSet<QString> listBoxIds;
    QSet<QString> treeViewIds;
    QMap<QString, QPair<int, int>> ranges;
};
}
