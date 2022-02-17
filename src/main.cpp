#include "context.hpp"
#include "imgui.h"
#include <iostream>
#include <memory>
#include <functional>

int main()
{
    std::shared_ptr<AppContext> app;
    try
    {
        app = std::make_shared<AppContext>();
    }
    catch(const std::exception& e)
    {
        std::cerr << e.what() << std::endl;
        return -1;
    }
    auto renderUI = [&]()
    {
        ImGui::SetNextWindowSize({300.0f, 200.0f}, ImGuiCond_FirstUseEver);
        ImGui::SetNextWindowPos({5.0f, 5.0f}, ImGuiCond_FirstUseEver);
        ImGui::Begin("UI");
        if(ImGui::BeginTabBar("Configs"))
        {
            if(ImGui::BeginTabItem("App"))
            {
                ImGui::EndTabItem();
            }
            ImGui::EndTabBar();
        }
        ImGui::End();
    };
    while(app->isAlive())
    {
        app->beginFrame();

        app->endFrame(renderUI);
    }
    return 0;
}
