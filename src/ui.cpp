#include "context.hpp"
#include "imgui.h"

void AppContext::UI()
{
    ImGui::Text("Window Size: %dx%d", _w, _h);
    ImGui::Text("FPS: %.2f", ImGui::GetIO().Framerate);
    ImGui::Checkbox("FPS Limit", &_fpsControl);
    ImGui::Text("Author: Teamclouday");
}