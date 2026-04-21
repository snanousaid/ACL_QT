#include "shmreader.h"

#include <QPainter>
#include <QDebug>
#include <cstring>

VideoItem::VideoItem(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    connect(&m_timer, &QTimer::timeout, this, &VideoItem::tick);
    m_timer.start(1000 / SHM_FPS);
}

VideoItem::~VideoItem()
{
    closeShm();
}

// ── Shared memory POSIX (Linux / Pi) ─────────────────────────────────

#ifdef Q_OS_LINUX

void VideoItem::openShm()
{
    m_fd = shm_open(SHM_NAME, O_RDONLY, 0);
    if (m_fd < 0) return;

    struct stat sb;
    if (fstat(m_fd, &sb) < 0) {
        close(m_fd);
        m_fd = -1;
        return;
    }

    m_size = static_cast<size_t>(sb.st_size);
    m_ptr  = mmap(nullptr, m_size, PROT_READ, MAP_SHARED, m_fd, 0);

    if (m_ptr == MAP_FAILED) {
        close(m_fd);
        m_fd = -1;
    }
}

void VideoItem::closeShm()
{
    if (m_ptr != MAP_FAILED) { munmap(m_ptr, m_size); m_ptr = MAP_FAILED; }
    if (m_fd  >= 0)           { close(m_fd);           m_fd  = -1;         }
}

void VideoItem::tick()
{
    // Tente d'ouvrir si pas encore connecté
    if (m_ptr == MAP_FAILED) {
        openShm();
        if (m_ptr == MAP_FAILED) return;
    }

    const auto *buf = static_cast<const uint8_t *>(m_ptr);

    // Lit frame_id et ready depuis le header
    uint32_t frameId = 0;
    memcpy(&frameId, buf + 0, 4);
    const uint8_t ready = buf[13];

    if (!ready || frameId == m_lastId) return;

    uint32_t w = 0, h = 0;
    memcpy(&w, buf + 4, 4);
    memcpy(&h, buf + 8, 4);

    if (w == 0 || h == 0) return;

    const uint8_t *pixels = buf + SHM_HEADER_SIZE;

    // Python écrit en BGR — Qt accepte BGR888 depuis Qt 5.14
#if QT_VERSION >= QT_VERSION_CHECK(5, 14, 0)
    QImage img(pixels, static_cast<int>(w), static_cast<int>(h),
               static_cast<int>(w * 3), QImage::Format_BGR888);
    m_frame = img.copy();   // détache de la mémoire partagée
#else
    QImage img(pixels, static_cast<int>(w), static_cast<int>(h),
               static_cast<int>(w * 3), QImage::Format_RGB888);
    m_frame = img.rgbSwapped();  // BGR → RGB
#endif

    m_lastId = frameId;
    update();
}

#else
// ── Stub non-Linux (compilation Windows/Mac pour dev) ────────────────

void VideoItem::openShm()  {}
void VideoItem::closeShm() {}

void VideoItem::tick()
{
    // Stub : affiche un dégradé de test
    if (m_frame.isNull())
        m_frame = QImage(640, 480, QImage::Format_RGB888);
    m_frame.fill(Qt::darkGray);
    update();
}

#endif

// ── Rendu QML ─────────────────────────────────────────────────────────

void VideoItem::paint(QPainter *painter)
{
    if (m_frame.isNull()) {
        painter->fillRect(boundingRect(), Qt::black);
        painter->setPen(Qt::gray);
        painter->setFont(QFont("Arial", 14));
        painter->drawText(boundingRect(), Qt::AlignCenter,
                          "En attente du flux Python...");
        return;
    }

    // Étire la frame à la taille du composant QML en conservant le ratio
    painter->drawImage(boundingRect(), m_frame);
}
