QT += quick network websockets virtualkeyboard
CONFIG += c++11

DEFINES += QT_DEPRECATED_WARNINGS

# ── OpenCV (A133 Linux uniquement) ────────────────────────────────────────
# ── OpenCV cross-compilation (A133 aarch64) ───────────────────────────────
# Headers + libs copiés depuis le A133 vers /opt/sysroot/a133 sur la VM.
# Sur Windows : bloc ignoré (win32 défini).
!win32 {
    A133_SYSROOT = /opt/sysroot/a133
    exists($$A133_SYSROOT/usr/include/opencv4) {
        INCLUDEPATH += $$A133_SYSROOT/usr/include/opencv4
        LIBS += -L$$A133_SYSROOT/usr/lib/aarch64-linux-gnu \
                -lopencv_core \
                -lopencv_videoio \
                -lopencv_imgproc \
                -lopencv_dnn \
                -lopencv_objdetect
        DEFINES += ACL_OPENCV_ENABLED
        message("OpenCV 4 (A133 sysroot) trouvé — face detection activée")
    } else {
        message("OpenCV 4 non trouvé — copier depuis A133 vers /opt/sysroot/a133")
    }
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
