#pragma once

#include <QQuickPaintedItem>
#include <QTimer>
#include <QImage>

#ifdef Q_OS_LINUX
#  include <sys/mman.h>
#  include <fcntl.h>
#  include <unistd.h>
#  include <sys/stat.h>
#endif

static constexpr int    SHM_HEADER_SIZE = 16;
static constexpr char   SHM_NAME[]      = "/acl_video_stream";
static constexpr int    SHM_FPS         = 30;

/**
 * VideoItem — QQuickPaintedItem qui lit les frames depuis la shared memory
 * écrite par Python (multiprocessing.shared_memory "acl_video_stream").
 *
 * Layout header (16 bytes) :
 *   [0..3]  frame_id  uint32
 *   [4..7]  width     uint32
 *   [8..11] height    uint32
 *   [12]    channels  uint8
 *   [13]    ready     uint8   (0=écriture, 1=prêt)
 *   [14..15] padding
 *   [16...] pixels BGR contiguous
 */
class VideoItem : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit VideoItem(QQuickItem *parent = nullptr);
    ~VideoItem() override;

    void paint(QPainter *painter) override;

private slots:
    void tick();

private:
    void openShm();
    void closeShm();

    QTimer   m_timer;
    QImage   m_frame;
    uint32_t m_lastId = 0;

#ifdef Q_OS_LINUX
    int    m_fd   = -1;
    void  *m_ptr  = MAP_FAILED;
    size_t m_size = 0;
#endif
};
