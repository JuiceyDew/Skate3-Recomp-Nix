#pragma once

#include <filesystem>

#include <rex/rex_app.h>

namespace skate3 {

bool IsGameInstalled(const std::filesystem::path& game_root);
bool RunRexglueIsoInstallWizardBlocking(rex::ui::WindowedAppContext& app_context,
                                        rex::ui::Window* window,
                                        rex::ui::ImGuiDrawer* drawer,
                                        rex::PathConfig runtime_paths,
                                        rex::PathConfig& installed_paths);

}  // namespace skate3
