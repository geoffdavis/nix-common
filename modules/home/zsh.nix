{lib, ...}: {
  programs.zsh = {
    enable = true;
    oh-my-zsh = {
      enable = true;
      theme = lib.mkDefault "agnoster";
      plugins = ["git" "python"];
    };
  };
}
