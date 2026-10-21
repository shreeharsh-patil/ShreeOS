#define _POSIX_C_SOURCE 200809L
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <errno.h>
#include <math.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define MAX_APPS 8
#define MIN_ICON 36
#define MAX_ICON 64
#define GAP 10
#define PAD 12
#define BOTTOM_GAP 12
#define HIDDEN_EDGE 4

/* Root polling interval used for screen geometry and theme changes. */
static const struct timespec poll_interval = {0, 200000000L};

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
    cfg.icon_size = 50;
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
            long parsed;
            errno = 0;
            parsed = strtol(value, &end, 10);
            /* An empty or unparsable value keeps the default icon size. */
            if (end && end != value && *end == '\0' && errno == 0)
                cfg.icon_size = clamp_int((int)parsed, MIN_ICON, MAX_ICON);
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


typedef struct {
    unsigned long files, terminal, browser, package, settings, other;
} DockPalette;

static int theme_is_dark(Display *dpy, Window root) {
    Atom property = XInternAtom(dpy, "_SHREEOS_THEME", False);
    Atom actual_type = None;
    int actual_format = 0;
    unsigned long item_count = 0, bytes_after = 0;
    unsigned char *value = NULL;
    int dark = 1;

    if (XGetWindowProperty(dpy, root, property, 0, 16, False, AnyPropertyType,
                           &actual_type, &actual_format, &item_count,
                           &bytes_after, &value) == Success && value && actual_format == 8) {
        if (item_count >= 5 && strncmp((const char *)value, "light", 5) == 0) dark = 0;
        XFree(value);
        return dark;
    }
    if (value) XFree(value);

    {
        const char *mode = getenv("SHREE_THEME_MODE");
        if (mode && strncmp(mode, "light", 5) == 0) return 0;
    }
    return 1;
}

static double glass_opacity(void) {
    const char *value = getenv("SHREE_GLASS_OPACITY");
    char *end = NULL;
    double opacity;
    if (!value || !*value) return 0.88;
    opacity = strtod(value, &end);
    if (!end || *end != '\0' || !isfinite(opacity) || opacity < 0.45 || opacity > 0.96) return 0.88;
    return opacity;
}

static void set_palette(Display *dpy, int screen, int dark, unsigned long *surface,
                        unsigned long *tile, unsigned long *tile_hover,
                        unsigned long *text, unsigned long *accent,
                        DockPalette *palette) {
    unsigned long fallback = BlackPixel(dpy, screen);
    if (dark) {
        *surface = named_pixel(dpy, screen, "#252527", fallback);
        *tile = named_pixel(dpy, screen, "#343438", fallback);
        *tile_hover = named_pixel(dpy, screen, "#45454B", WhitePixel(dpy, screen));
        *text = named_pixel(dpy, screen, "#FFFDFA", WhitePixel(dpy, screen));
    } else {
        *surface = named_pixel(dpy, screen, "#F4EFE9", WhitePixel(dpy, screen));
        *tile = named_pixel(dpy, screen, "#E7E0D9", WhitePixel(dpy, screen));
        *tile_hover = named_pixel(dpy, screen, "#D8CFC6", WhitePixel(dpy, screen));
        *text = named_pixel(dpy, screen, "#29313D", BlackPixel(dpy, screen));
    }
    *accent = named_pixel(dpy, screen, "#2878FF", WhitePixel(dpy, screen));
    palette->files = named_pixel(dpy, screen, "#3289E8", *accent);
    palette->terminal = named_pixel(dpy, screen, dark ? "#4B5567" : "#667085", *surface);
    palette->browser = named_pixel(dpy, screen, "#1797B3", *accent);
    palette->package = named_pixel(dpy, screen, "#8060D9", *accent);
    palette->settings = named_pixel(dpy, screen, dark ? "#677589" : "#758197", *surface);
    palette->other = named_pixel(dpy, screen, dark ? "#477A9F" : "#4383A8", *accent);
}

/* Xlib-only rounded icon surfaces keep the native ISO dependency-free. */
static void fill_rounded(Display *dpy, Drawable target, GC gc,
                         int x, int y, int w, int h, int radius) {
    int diameter = radius * 2;
    XFillRectangle(dpy, target, gc, x + radius, y, (unsigned int)(w - diameter), (unsigned int)h);
    XFillRectangle(dpy, target, gc, x, y + radius, (unsigned int)w, (unsigned int)(h - diameter));
    XFillArc(dpy, target, gc, x, y, (unsigned int)diameter, (unsigned int)diameter, 90 * 64, 90 * 64);
    XFillArc(dpy, target, gc, x + w - diameter, y, (unsigned int)diameter, (unsigned int)diameter, 0, 90 * 64);
    XFillArc(dpy, target, gc, x, y + h - diameter, (unsigned int)diameter, (unsigned int)diameter, 180 * 64, 90 * 64);
    XFillArc(dpy, target, gc, x + w - diameter, y + h - diameter, (unsigned int)diameter, (unsigned int)diameter, 270 * 64, 90 * 64);
}

static unsigned long app_color(const char *app, const DockPalette *p) {
    if (strcmp(app, "shree-files") == 0) return p->files;
    if (strcmp(app, "st") == 0) return p->terminal;
    if (strcmp(app, "netsurf") == 0 || strcmp(app, "shree-browser") == 0) return p->browser;
    if (strcmp(app, "shree-pkgmanager") == 0) return p->package;
    if (strcmp(app, "shree-settings") == 0) return p->settings;
    return p->other;
}

/* Distinct vector icons replace the old two-letter dock placeholders. */
static void draw_app_icon(Display *dpy, Drawable target, GC gc, XFontStruct *font,
                          const char *app, int x, int y, int size, unsigned long ink) {
    int cx = x + size / 2, cy = y + size / 2;
    int r = size / 4;
    XSetForeground(dpy, gc, ink);
    XSetLineAttributes(dpy, gc, 2, LineSolid, CapRound, JoinRound);
    if (strcmp(app, "shree-files") == 0) {
        XDrawRectangle(dpy, target, gc, cx - r, cy - r / 2, (unsigned int)(2 * r), (unsigned int)(r + r / 2));
        XDrawLine(dpy, target, gc, cx - r, cy - r / 2, cx - r + r / 2, cy - r);
        XDrawLine(dpy, target, gc, cx - r + r / 2, cy - r, cx + r / 2, cy - r);
        XDrawLine(dpy, target, gc, cx - r + r / 2, cy - r / 2, cx + r / 2, cy - r / 2);
    } else if (strcmp(app, "st") == 0) {
        XDrawLine(dpy, target, gc, cx - r, cy - r / 2, cx - 2, cy);
        XDrawLine(dpy, target, gc, cx - 2, cy, cx - r, cy + r / 2);
        XDrawLine(dpy, target, gc, cx + 1, cy + r / 2, cx + r, cy + r / 2);
    } else if (strcmp(app, "netsurf") == 0 || strcmp(app, "shree-browser") == 0) {
        XDrawArc(dpy, target, gc, cx - r, cy - r, (unsigned int)(2 * r), (unsigned int)(2 * r), 0, 360 * 64);
        XDrawArc(dpy, target, gc, cx - r / 2, cy - r, (unsigned int)r, (unsigned int)(2 * r), 0, 360 * 64);
        XDrawLine(dpy, target, gc, cx - r, cy, cx + r, cy);
    } else if (strcmp(app, "shree-pkgmanager") == 0 || strcmp(app, "shree-apps") == 0) {
        XDrawRectangle(dpy, target, gc, cx - r, cy - r / 2, (unsigned int)(2 * r), (unsigned int)(r + r / 2));
        XDrawArc(dpy, target, gc, cx - r / 2, cy - r, (unsigned int)r, (unsigned int)r, 0, 180 * 64);
    } else if (strcmp(app, "shree-settings") == 0 || strcmp(app, "shree-control-center") == 0) {
        int k;
        static const int vx[8] = {0, 7, 10, 7, 0, -7, -10, -7};
        static const int vy[8] = {-10, -7, 0, 7, 10, 7, 0, -7};
        XDrawArc(dpy, target, gc, cx - r / 2, cy - r / 2, (unsigned int)r, (unsigned int)r, 0, 360 * 64);
        for (k = 0; k < 8; ++k)
            XDrawLine(dpy, target, gc, cx + vx[k] * r / 10, cy + vy[k] * r / 10,
                      cx + vx[k] * (r + 4) / 10, cy + vy[k] * (r + 4) / 10);
    } else {
        const char *label = label_for(app);
        int tw = XTextWidth(font, label, (int)strlen(label));
        XDrawString(dpy, target, gc, cx - tw / 2, cy + (font->ascent - font->descent) / 2,
                    label, (int)strlen(label));
    }
    XSetLineAttributes(dpy, gc, 0, LineSolid, CapButt, JoinMiter);
}

static void draw_dock(Display *dpy, Window win, GC gc, XFontStruct *font,
                      const DockConfig *cfg, int width, int height, int hover,
                      unsigned long surface, unsigned long tile,
                      unsigned long tile_hover, unsigned long text,
                      unsigned long accent, const DockPalette *palette) {
    int i;
    XSetForeground(dpy, gc, surface);
    XFillRectangle(dpy, win, gc, 0, 0, (unsigned int)width, (unsigned int)height);

    for (i = 0; i < cfg->app_count; ++i) {
        int x = PAD + i * (cfg->icon_size + GAP);
        int y = PAD - 2;
        int size = cfg->icon_size;
        int radius = size / 5;
        unsigned long base = app_color(cfg->apps[i], palette);

        XSetForeground(dpy, gc, base);
        fill_rounded(dpy, win, gc, x, y, size, size, radius);
        if (i == hover) {
            XSetForeground(dpy, gc, tile_hover);
            XDrawRectangle(dpy, win, gc, x - 2, y - 2,
                           (unsigned int)(size + 3), (unsigned int)(size + 3));
        }
        draw_app_icon(dpy, win, gc, font, cfg->apps[i], x, y, size, text);
        if (i == hover) {
            XSetForeground(dpy, gc, accent);
            XFillArc(dpy, win, gc, x + size / 2 - 2, height - 7, 4, 4, 0, 360 * 64);
        }
    }
    (void)tile;
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
    unsigned long root;
    int dark;
    DockPalette palette;

    if (!dpy) {
        fprintf(stderr, "shree-dock-ui: cannot open X display\n");
        return 1;
    }
    signal(SIGCHLD, SIG_IGN);

    screen = DefaultScreen(dpy);
    root = RootWindow(dpy, screen);
    sw = DisplayWidth(dpy, screen);
    sh = DisplayHeight(dpy, screen);
    width = PAD * 2 + cfg.app_count * cfg.icon_size + (cfg.app_count - 1) * GAP;
    height = cfg.icon_size + PAD * 2;
    visible_y = sh - height - BOTTOM_GAP;
    hidden_y = sh - HIDDEN_EDGE;

    dark = theme_is_dark(dpy, root);
    set_palette(dpy, screen, dark, &surface, &tile, &tile_hover, &text, &accent, &palette);

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
    set_opacity(dpy, win, (unsigned long)(glass_opacity() * 4294967295.0));

    font = XLoadQueryFont(dpy, "fixed");
    if (!font) font = XQueryFont(dpy, XGContextFromGC(DefaultGC(dpy, screen)));
    if (!font) {
        fprintf(stderr, "shree-dock-ui: no usable font could be loaded\n");
        XCloseDisplay(dpy);
        return 1;
    }
    gcv.font = font->fid;
    gc = XCreateGC(dpy, win, GCFont, &gcv);

    /* The window manager already owns StructureNotifyMask and
     * PropertyChangeMask on the root window, and X11 allows only one client
     * per exclusive event type.  Selecting them here makes the window
     * manager fail with BadAccess, so the dock polls the root in the event
     * loop instead of selecting the root events. */
    XMapRaised(dpy, win);
    XFlush(dpy);

    for (;;) {
        /* Polling the root keeps the dock centred on screen resize and
         * follows theme changes without taking the window manager's
         * exclusive root events. */
        if (!XPending(dpy)) {
            XWindowAttributes root_attributes;
            int current_width = sw;
            int current_height = sh;
            int current_dark;
            /* The cached screen size only changes when the client receives
             * the root events, so the root geometry is queried directly. */
            if (XGetWindowAttributes(dpy, root, &root_attributes)) {
                current_width = root_attributes.width;
                current_height = root_attributes.height;
            }
            current_dark = theme_is_dark(dpy, root);
            if (current_width != sw || current_height != sh) {
                sw = current_width;
                sh = current_height;
                visible_y = sh - height - BOTTOM_GAP;
                hidden_y = sh - HIDDEN_EDGE;
                XMoveWindow(dpy, win, (sw - width) / 2, hidden ? hidden_y : visible_y);
            }
            if (current_dark != dark) {
                dark = current_dark;
                set_palette(dpy, screen, dark, &surface, &tile, &tile_hover, &text, &accent, &palette);
                XSetWindowBackground(dpy, win, surface);
                XClearWindow(dpy, win);
                draw_dock(dpy, win, gc, font, &cfg, width, height, hover,
                          surface, tile, tile_hover, text, accent, &palette);
            }
            nanosleep(&poll_interval, NULL);
            continue;
        }
        XNextEvent(dpy, &ev);
        switch (ev.type) {
            case Expose:
                if (ev.xexpose.count == 0)
                    draw_dock(dpy, win, gc, font, &cfg, width, height, hover,
                              surface, tile, tile_hover, text, accent, &palette);
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
                              surface, tile, tile_hover, text, accent, &palette);
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
                              surface, tile, tile_hover, text, accent, &palette);
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
