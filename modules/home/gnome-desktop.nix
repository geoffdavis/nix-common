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
  };
}
