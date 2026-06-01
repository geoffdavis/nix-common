{...}: {
  dconf.settings = {
    "org/gnome/shell" = {
      enabled-extensions = [
        "tilingshell@ferrarodomenico.com"
        "clipboard-indicator@tudmotu.com"
        "cpupower@mko-sl.de"
        "gsconnect@andyholmes.github.io"
        "gnome-kinit@bonzini.gnu.org"
        "espresso@coadmunkee.github.com"
        "this.simple-indication-of-workspaces@azate.email"
        "night-light-toggle@egoistpizza.github.com"
        "xremap@k0kubun.com"
        "apps-menu@gnome-shell-extensions.gcampax.github.com"
        "nightthemeswitcher@romainvigier.fr"
        "dbus-workspace-control@local"
      ];
    };
    "org/gnome/mutter" = {
      experimental-features = [
        "scale-monitor-framebuffer"
      ];
    };

    # 1Password global shortcuts (Wayland requires compositor-level registration)
    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/"
      ];
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      name = "1Password Quick Access";
      command = "1password --quick-access";
      binding = "<Control><Shift>space";
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1" = {
      name = "1Password Fill in Browser";
      command = "1password --fill";
      binding = "<Control>backslash";
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2" = {
      name = "1Password Lock";
      command = "1password --lock";
      binding = "<Control><Shift>l";
    };
  };
}
