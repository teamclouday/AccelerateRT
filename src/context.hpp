#pragma once
#include <GL/glew.h>
#include <GLFW/glfw3.h>
#include <string>
#include <functional>

#define CONTEXT_FPS 60
#define CONTEXT_SPF 0.016666666

class AppContext
{
public:
    AppContext();
    AppContext(int width, int height, const std::string& title);
    ~AppContext();

    bool isAlive();
    void beginFrame();
    void endFrame(std::function<void()> customUI = nullptr);

    void UI();

private:
    void initContext();

    int _w, _h;
    const std::string _title;
    GLFWwindow* _window;
    double _timer = 0.0;
    bool _fpsControl = false;
    bool _displayUI = true;

    static void glfw_key_callback(GLFWwindow* window, int key, int scancode, int action, int mods)
    {
        AppContext* user = reinterpret_cast<AppContext*>(glfwGetWindowUserPointer(window));
        if(action == GLFW_PRESS)
        {
            switch(key)
            {
                case GLFW_KEY_ESCAPE:
                    glfwSetWindowShouldClose(window, GLFW_TRUE);
                    break;
                case GLFW_KEY_F12:
                    user->_displayUI = !user->_displayUI;
                    break;
            }
        }
    }
};
