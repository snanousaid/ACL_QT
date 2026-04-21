QT += quick core gui
CONFIG += c++11

DEFINES += QT_DEPRECATED_WARNINGS

SOURCES += \
    main.cpp \
    shmreader.cpp

HEADERS += \
    shmreader.h

RESOURCES += qml.qrc

# Lien avec librt pour shm_open sur Linux
linux: LIBS += -lrt

QML_IMPORT_PATH =
QML_DESIGNER_IMPORT_PATH =

qnx: target.path = /tmp/$${TARGET}/bin
else: unix:!android: target.path = /opt/$${TARGET}/bin
!isEmpty(target.path): INSTALLS += target
