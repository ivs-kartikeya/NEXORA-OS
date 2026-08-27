cmake_minimum_required(VERSION 3.21)
project(NexoraOS VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.4 REQUIRED COMPONENTS Core Gui Qml Quick Network DBus)
qt_standard_project_setup()

qt_add_executable(nexora-shell
    src/main.cpp
    src/systembackend.cpp
    src/systembackend.h
)

qt_add_resources(nexora-shell "nexora_qml"
    PREFIX "/Nexora"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/qml"
    FILES qml/Main.qml
)

target_link_libraries(nexora-shell PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Network Qt6::DBus util
)

qt_add_executable(nexora-core
    src/core_main.cpp
    src/coredaemon.cpp
    src/coredaemon.h
)

target_link_libraries(nexora-core PRIVATE Qt6::Core Qt6::Network Qt6::DBus)

install(TARGETS nexora-shell nexora-core RUNTIME DESTINATION bin)
