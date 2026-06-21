use zed_extension_api::{self as zed, serde_json, settings::LspSettings, LanguageServerId, Result};

struct ZiexExtension;

impl zed::Extension for ZiexExtension {
    fn new() -> Self {
        Self
    }

    fn language_server_command(
        &mut self,
        _language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<zed::Command> {
        let (platform, _) = zed::current_platform();
        let env = match platform {
            zed::Os::Mac | zed::Os::Linux => worktree.shell_env(),
            zed::Os::Windows => vec![],
        };

        // Respect custom binary path from LSP settings
        if let Ok(lsp_settings) = LspSettings::for_worktree("zxls", worktree) {
            if let Some(binary) = lsp_settings.binary {
                if let Some(path) = binary.path {
                    return Ok(zed::Command {
                        command: path,
                        args: binary.arguments.unwrap_or_default(),
                        env,
                    });
                }
            }
        }

        // Use `zx lsp` if zx is in PATH, otherwise fall back to `zig build zx -Dziex-lsp=true -- lsp`
        if let Some(zx_path) = worktree.which("zx") {
            Ok(zed::Command { command: zx_path, args: vec!["lsp".into()], env })
        } else {
            let zig_path = worktree
                .which("zig")
                .ok_or("Neither zx nor zig found in PATH.")?;
            Ok(zed::Command {
                command: zig_path,
                args: vec!["build".into(), "zx".into(), "-Dziex-lsp=true".into(), "--".into(), "lsp".into()],
                env,
            })
        }
    }

    fn language_server_workspace_configuration(
        &mut self,
        _language_server_id: &zed::LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<Option<serde_json::Value>> {
        let settings = LspSettings::for_worktree("zxls", worktree)
            .ok()
            .and_then(|lsp_settings| lsp_settings.settings.clone())
            .unwrap_or_default();
        Ok(Some(settings))
    }

}

zed::register_extension!(ZiexExtension);
