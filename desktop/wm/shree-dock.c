#define _POSIX_C_SOURCE 200809L
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MAX_APPS 8
#define MIN_ICON 36
#define MAX_ICON 64
#define GAP 10
#define PAD 12
#define BOTTOM_GAP 12
#define HIDDEN_EDGE 4

typedef struct {
    int icon_size;
    int autohide;
    int app_count;
    char apps[MAX_APPS][64];
} DockConfig;

static void trim(char *s);

static const char *label_for(const char *app) {
    if (strcmp(app, "shree-files") == 0) return "Fi";
    if (strcmp(app, "st") == 0) return "Te";
    if (strcmp(app, "netsurf") == 0 || strcmp(app, "shree-browser") == 0) return "Br";
    if (strcmp(app, "shree-pkgmanager") == 0) return "Pk";
    if (strcmp(app, "shree-settings") == 0) return "Se";
    if (strcmp(app, "shree-apps") == 0) return "Ap";
    if (strcmp(app, "shree-edit") == 0) return "Ed";
    if (strcmp(app, "shree-sysmon") == 0) return "Ac";
    return "OS";
}

static void load_default_apps(DockConfig *cfg) {
    static const char *defaults[] = {
        "shree-files", "st", "netsurf", "shree-pkgmanager", "shree-settings"
    };
    size_t i;
    cfg->app_count = 0;
    for (i = 0; i < sizeof(defaults) / sizeof(defaults[0]); ++i) {
        snprintf(cfg->apps[cfg->app_count], sizeof(cfg->apps[cfg->app_count]), "%s", defaults[i]);
        cfg->app_count++;
    }
}

static void parse_apps(DockConfig *cfg, const char *value) {
    char copy[512];
    char *save = NULL;
    char *token;
    cfg->app_count = 0;
    snprintf(copy, sizeof(copy), "%s", value);
    token = strtok_r(copy, ":", &save);
    while (token && cfg->app_count < MAX_APPS) {
        trim(token);
        if (*token) {
            snprintf(cfg->apps[cfg->app_count], sizeof(cfg->apps[cfg->app_count]), "%s", token);
            cfg->app_count++;
        }
        token = strtok_r(NULL, ":", &save);
    }
    if (cfg->app_count == 0) load_default_apps(cfg);
}

static int clamp_int(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
}

static void trim(char *s) {
    size_t len;
    while (*s == ' ' || *s == '\t') memmove(s, s + 1, strlen(s));
    len = strlen(s);
    while (len > 0 && (s[len - 1] == '\n' || s[len - 1] == '\r' ||
                       s[len - 1] == ' ' || s[len - 1] == '\t')) {
        s[--len] = '\0';
    }
    if (len >= 2 && s[0] == '"' && s[len - 1] == '"') {
        memmove(s, s + 1, len - 2);
        s[len - 2] = '\0';
    }
}

static DockConfig load_config(void) {
    DockConfig cfg;
    const char *home;
    char path[4096];
    FILE *f;
    char line[512];

    memset(&cfg, 0, sizeof(cfg));
    cfg.icon_size = 44;
    load_default_apps(&cfg);

    home = getenv("HOME");
    if (!home || !*home) return cfg;
    if (snprintf(path, sizeof(path), "%s/.config/shreeos/dock.conf", home) >= (int)sizeof(path)) return cfg;
    f = fopen(path, "r");
    if (!f) return cfg;

    while (fgets(line, sizeof(line), f)) {
        char *eq = strchr(line, '=');
        char *key;
        char *value;
        if (!eq) continue;
        *eq = '\0';
        key = line;
        value = eq + 1;
        trim(key);
        trim(value);

        if (strcmp(key, "ICON_SIZE") == 0) {
            char *end = NULL;
            long parsed = strtol(value, &end, 10);
            if (end && *end == '\0') cfg.icon_size = clamp_int((int)parsed, MIN_ICON, MAX_ICON);
        } else if (strcmp(key, "AUTOHIDE") == 0) {
            cfg.autohide = strcmp(value, "true") == 0 || strcmp(value, "1") == 0;
        } else if (strcmp(key, "PINNED_APPS") == 0) {
            parse_apps(&cfg, value);
        }
    }
    fclose(f);
    return cfg;
}

static unsigned long named_pixel(Display *dpy, int screen, const char *name, unsigned long fallback) {
    XColor exact, screen_color;
    Colormap cmap = DefaultColormap(dpy, screen);
    if (XAllocNamedColor(dpy, cmap, name, &screen_color, &exact)) return screen_color.pixel;
    return fallback;
}

static void set_atom(Display *dpy, Window win, const char *property_name, const char *value_name) {
    Atom prop = XInternAtom(dpy, property_name, False);
    Atom value = XInternAtom(dpy, value_name, False);
    XChangeProperty(dpy, win, prop, XA_ATOM, 32, PropModeReplace, (unsigned char *)&value, 1);
}

static void set_opacity(Display *dpy, Window win, unsigned long opacity) {
    Atom prop = XInternAtom(dpy, "_NET_WM_WINDOW_OPACITY", False);
    XChangeProperty(dpy, win, prop, XA_CARDINAL, 32, PropModeReplace, (unsigned char *)&opacity, 1);
}

static void launch_app(const char *app) {
    pid_t pid = fork();
    if (pid < 0) return;
    if (pid == 0) {
        execl("/usr/bin/shree-dock", "shree-dock", "launch", app, (char *)NULL);
        execlp("shree-dock", "shree-dock", "launch", app, (char *)NULL);
        _exit(127);
    }
}

static void draw_dock(Display *dpy, Window win, GC gc, XFontStruct *font,
                      const DockConfig *cfg, int width, int height, int hover,
                      unsigned long surface, unsigned long tile,
                      unsigned long tile_hover, unsigned long text,
                      unsigned long accent) {
    int i;
    XSetForeground(dpy, gc, surface);
    XFillRectangle(dpy, win, gc, 0, 0, (unsigned int)width, (unsigned int)height);

    for (i = 0; i < cfg->app_count; ++i) {
        const char *label = label_for(cfg->apps[i]);
        int x = PAD + i * (cfg->icon_size + GAP);
        int y = PAD - 2;
        int tw = XTextWidth(font, label, (int)strlen(label));
        int tx = x + (cfg->icon_size - tw) / 2;
        int ty = y + (cfg->icon_size + font->ascent - font->descent) / 2;

        XSetForeground(dpy, gc, i == hover ? tile_hover : tile);
        XFillRectangle(dpy, win, gc, x, y, (unsigned int)cfg->icon_size, (unsigned int)cfg->icon_size);
        XSetForeground(dpy, gc, text);
        XDrawString(dpy, win, gc, tx, ty, label, (int)strlen(label));

        if (i == hover) {
            XSetForeground(dpy, gc, accent);
            XFillRectangle(dpy, win, gc, x + cfg->icon_size / 2 - 2, height - 6, 4, 2);
        }
    }
}

int main(void) {
    DockConfig cfg = load_config();
    Display *dpy = XOpenDisplay(NULL);
    int screen;
    int sw, sh, width, height, visible_y, hidden_y;
    XSetWindowAttributes attrs;
    Window win;
    XClassHint hint;
    XGCValues gcv;
    GC gc;
    XFontStruct *font;
    XEvent ev;
    int hover = -1;
    int hidden = 0;
    unsigned long surface, tile, tile_hover, text, accent;

    if (!dpy) {
        fprintf(stderr, "shree-dock-ui: cannot open X display\n");
        return 1;
    }
    signal(SIGCHLD, SIG_IGN);

    screen = DefaultScreen(dpy);
    sw = DisplayWidth(dpy, screen);
    sh = DisplayHeight(dpy, screen);
    width = PAD * 2 + cfg.app_count * cfg.icon_size + (cfg.app_count - 1) * GAP;
    height = cfg.icon_size + PAD * 2;
    visible_y = sh - height - BOTTOM_GAP;
    hidden_y = sh - HIDDEN_EDGE;

    surface = named_pixel(dpy, screen, "#2C2C2E", BlackPixel(dpy, screen));
    tile = named_pixel(dpy, screen, "#3A3A3C", BlackPixel(dpy, screen));
    tile_hover = named_pixel(dpy, screen, "#48484A", WhitePixel(dpy, screen));
    text = named_pixel(dpy, screen, "#F5F5F7", WhitePixel(dpy, screen));
    accent = named_pixel(dpy, screen, "#2878FF", WhitePixel(dpy, screen));

    attrs.override_redirect = True;
    attrs.background_pixel = surface;
    attrs.event_mask = ExposureMask | ButtonPressMask | PointerMotionMask |
                       EnterWindowMask | LeaveWindowMask;

    win = XCreateWindow(dpy, RootWindow(dpy, screen), (sw - width) / 2, visible_y,
                        (unsigned int)width, (unsigned int)height, 0,
                        CopyFromParent, InputOutput, CopyFromParent,
                        CWOverrideRedirect | CWBackPixel | CWEventMask, &attrs);

    hint.res_name = "shree-dock-ui";
    hint.res_class = "ShreeDock";
    XSetClassHint(dpy, win, &hint);
    XStoreName(dpy, win, "ShreeOS Dock");
    set_atom(dpy, win, "_NET_WM_WINDOW_TYPE", "_NET_WM_WINDOW_TYPE_DOCK");
    set_opacity(dpy, win, 0xE6FFFFFFUL);

    font = XLoadQueryFont(dpy, "fixed");
    if (!font) font = XQueryFont(dpy, XGContextFromGC(DefaultGC(dpy, screen)));
    gcv.font = font->fid;
    gc = XCreateGC(dpy, win, GCFont, &gcv);

    XMapRaised(dpy, win);
    XFlush(dpy);

    for (;;) {
        XNextEvent(dpy, &ev);
        switch (ev.type) {
            case Expose:
                if (ev.xexpose.count == 0)
                    draw_dock(dpy, win, gc, font, &cfg, width, height, hover,
                              surface, tile, tile_hover, text, accent);
                break;

            case MotionNotify: {
                int rel = ev.xmotion.x - PAD;
                int slot = cfg.icon_size + GAP;
                int next = -1;
                if (rel >= 0) {
                    int idx = rel / slot;
                    int within = rel % slot;
                    if (idx >= 0 && idx < cfg.app_count && within < cfg.icon_size) next = idx;
                }
                if (next != hover) {
                    hover = next;
                    draw_dock(dpy, win, gc, font, &cfg, width, height, hover,
                              surface, tile, tile_hover, text, accent);
                }
                break;
            }

            case ButtonPress: {
                int rel = ev.xbutton.x - PAD;
                int slot = cfg.icon_size + GAP;
                if (rel >= 0) {
                    int idx = rel / slot;
                    int within = rel % slot;
                    if (idx >= 0 && idx < cfg.app_count && within < cfg.icon_size)
                        launch_app(cfg.apps[idx]);
                }
                break;
            }

            case LeaveNotify:
                hover = -1;
                if (cfg.autohide && !hidden) {
                    XMoveWindow(dpy, win, (sw - width) / 2, hidden_y);
                    hidden = 1;
                } else {
                    draw_dock(dpy, win, gc, font, &cfg, width, height, hover,
                              surface, tile, tile_hover, text, accent);
                }
                break;

            case EnterNotify:
                if (cfg.autohide && hidden) {
                    XMoveWindow(dpy, win, (sw - width) / 2, visible_y);
                    XRaiseWindow(dpy, win);
                    hidden = 0;
                }
                break;

            default:
                break;
        }
    }
}
