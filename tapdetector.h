#pragma once
#include <QObject>
#include <QEvent>
#include <QMouseEvent>
#include <QTouchEvent>
#include <QDateTime>

// ─────────────────────────────────────────────────────────────────────────────
// TapDetector — Event filter au niveau application, capture les MouseButtonPress
// et TouchBegin sans les consommer. Émet `tapped()` à chaque tap.
//
// Évite le bug A133 eglfs/evdev où MultiPointTouchArea capture les touches
// sans recevoir les releases (ghost touch ID 3000001), ce qui provoque
// les warnings "TouchPointPressed without previous release event" et bloque
// les taps suivants.
//
// L'event filter observe les événements au niveau Qt App AVANT qu'ils
// n'atteignent le QML, sans les accepter → propagation normale derrière.
// ─────────────────────────────────────────────────────────────────────────────
class TapDetector : public QObject
{
    Q_OBJECT
public:
    explicit TapDetector(QObject *parent = nullptr) : QObject(parent) {}

signals:
    void tapped();

protected:
    bool eventFilter(QObject *obj, QEvent *event) override
    {
        const QEvent::Type t = event->type();

        // Mouse press (synthétisé depuis touch sur eglfs, ou natif sur desktop)
        if (t == QEvent::MouseButtonPress) {
            fire();
        }
        // Touch begin (utile si la synthèse mouse est désactivée)
        else if (t == QEvent::TouchBegin) {
            fire();
        }

        return false;   // ne consomme JAMAIS l'événement → propagation normale
    }

private:
    void fire()
    {
        // Déduplication 80 ms : Qt peut envoyer TouchBegin + MouseButtonPress
        // pour le même tap (sur eglfs avec synthèse mouse activée).
        const qint64 now = QDateTime::currentMSecsSinceEpoch();
        if (now - m_lastFireMs < 80) return;
        m_lastFireMs = now;
        emit tapped();
    }

    qint64 m_lastFireMs = 0;
};
