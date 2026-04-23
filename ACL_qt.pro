QT += quick network websockets virtualkeyboard
CONFIG += c++11

DEFINES += QT_DEPRECATED_WARNINGS

# ── OpenCV (A133 Linux uniquement) ────────────────────────────────────────
unix {
    CONFIG += link_pkgconfig
    PKGCONFIG += opencv4
    DEFINES += ACL_OPENCV_ENABLED
}

SOURCES += \
    main.cpp \
    mjpegitem.cpp \
    socketioclient.cpp \
    appcontroller.cpp \
    opencvtest.cpp

HEADERS += \
    mjpegitem.h \
    socketioclient.h \
    appcontroller.h \
    opencvtest.h

RESOURCES += qml.qrc

QML_IMPORT_PATH =
QML_DESIGNER_IMPORT_PATH =

qnx: target.path = /tmp/$${TARGET}/bin
else: unix:!android: target.path = /opt/$${TARGET}/bin
!isEmpty(target.path): INSTALLS += target
