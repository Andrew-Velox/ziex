# Ziex App on Render

> A starter template for building web applications with [Ziex](https://ziex.dev) deployed on [Render](https://render.com/).

**[Documentation →](https://ziex.dev)**

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/ziex-dev/template-render)

## Getting Started

### Prerequisites

**1. Install ZX CLI**

```bash
# Linux/macOS
curl -fsSL https://ziex.dev/install | bash

# Windows
powershell -c "irm ziex.dev/install.ps1 | iex"
```

**2. Install Zig**

```bash
brew install zig  # macOS
winget install -e --id zig.zig  # Windows
```

[_Other platforms →_](https://ziglang.org/learn/getting-started/)

## Project Structure

```
├── app/
│   ├── assets/         # Static assets (CSS, images, etc)
│   ├── main.zig        # Zig entrypoint
│   ├── pages/          # Pages (Zig/ZX)
│   │   ├── layout.zx   # Root layout
│   │   ├── page.zx     # Home page
│   │   ├── client.zx   # Client-side component
│   │   └── ...
│   └── public/         # Public static files (favicon, etc)
├── build.zig           # Zig build script
└── build.zig.zon       # Zig package manager config
```

## Development

```bash
zig build dev
```

App will be available at [`http://localhost:3000`](http://localhost:3000) with hot reload enabled.

## Deploy to Render

### Via Render Dashboard

1. Push this repo to GitHub
2. Go to [Render](https://render.com/) and create a new **Web Service**
3. Select **Deploy from GitHub repo**
4. Render will auto-detect the `render.yaml` blueprint and configure:
   - **Environment**: Docker
   - **Dockerfile Path**: `./Dockerfile`
   - **Health Check Path**: `/`

### Via Blueprint

This template includes a `render.yaml` blueprint. Click the deploy button above or:

1. Go to [Render Blueprint Dashboard](https://dashboard.render.com/select-repo?type=blueprint)
2. Select this repository
3. Render will read `render.yaml` and configure the service automatically

### Configuration

The app automatically reads the `PORT` environment variable provided by Render and binds to `0.0.0.0`. No manual port configuration is needed.

## Contributing

Contributions are welcome! For feature requests, bug reports, or questions, see the [Ziex Repo](https://github.com/ziex-dev/ziex).

## Links

- [Documentation](https://ziex.dev)
- [Discord](https://ziex.dev/r/discord)
- [Render Docs](https://render.com/docs)
- [Zig Language](https://ziglang.org/)
