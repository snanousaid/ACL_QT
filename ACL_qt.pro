QT += quick network websockets
CONFIG += c++11

DEFINES += QT_DEPRECATED_WARNINGS

SOURCES += \
    main.cpp \
    mjpegitem.cpp \
    socketioclient.cpp \
    appcontroller.cpp

HEADERS += \
    mjpegitem.h \
    socketioclient.h \
    appcontroller.h

RESOURCES += qml.qrc

QML_IMPORT_PATH =
QML_DESIGNER_IMPORT_PATH =

qnx: target.path = /tmp/$${TARGET}/bin
else: unix:!android: target.path = /opt/$${TARGET}/bin
!isEmpty(target.path): INSTALLS += target
