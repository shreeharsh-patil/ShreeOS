/*
 * desktop/configs/dwm-config.h — ShreeOS dwm Window Manager Configuration
 *
 * Polished layout, Inter typography, restrained cool blue accents,
 * 28px top bar height, and Super-key shortcuts.
 */

#ifndef DWM_CONFIG_H
#define DWM_CONFIG_H

#include <X11/XF86keysym.h>

/* --- Appearance & Visual Styling --------------------------------------- */
static const unsigned int borderpx  = 1;        /* 1px crisp window border */
static const unsigned int snap      = 16;       /* Snap pixel distance */
static const int showbar            = 1;        /* 0 means no bar */
static const int topbar             = 1;        /* 1 means top bar (28px height) */
static const unsigned int user_bh   = 28;       /* Custom top bar height in pixels */

static const char *fonts[]          = { "Inter:size=10:weight=medium:antialias=true:autohint=true",
                                        "monospace:size=10" };
static const char dmenufont[]       = "Inter:size=11:weight=regular:antialias=true:autohint=true";

/* --- Color System (Dark Neutral + ShreeOS Accent) ---------------------- */
static const char col_bg[]          = "#1C1C1E"; /* Dark primary surface */
static const char col_bg_sel[]      = "#242426"; /* Selected elevated surface */
static const char col_fg[]          = "#A1A1A6"; /* Secondary metadata text */
static const char col_fg_sel[]      = "#F5F5F7"; /* Primary text */
static const char col_border[]      = "#2E2E32"; /* Inactive window rim */
static const char col_border_sel[]  = "#2878FF"; /* Focused ShreeOS blue accent */

static const char *colors[][3]      = {
    /*               fg         bg          border   */
    [SchemeNorm] = { col_fg,     col_bg,     col_border },
    [SchemeSel]  = { col_fg_sel, col_bg_sel, col_border_sel },
};

/* --- Workspaces / Tagging (Calm, Numbered Workspaces) ------------------ */
static const char *tags[] = { "1", "2", "3", "4" };

/* --- Window Rules ------------------------------------------------------ */
static const Rule rules[] = {
    /* class          instance    title       tags mask     isfloating   monitor */
    { "ShreeAbout",   NULL,       NULL,       0,            1,           -1 },
    { "ShreeSettings",NULL,       NULL,       0,            1,           -1 },
    { "ShreeControl", NULL,       NULL,       0,            1,           -1 },
    { "ShreeDock",    NULL,       NULL,       0,            1,           -1 },
    { "ShreeNotify",  NULL,       NULL,       0,            1,           -1 },
    { "ShreeApps",    NULL,       NULL,       0,            0,           -1 },
    { "ShreeFiles",   NULL,       NULL,       0,            0,           -1 },
};

/* --- Layouts ----------------------------------------------------------- */
static const float mfact     = 0.55; /* Master area factor [0.05..0.95] */
static const int nmaster     = 1;    /* Number of clients in master area */
static const int resizehints = 0;    /* 1 means respect size hints in tiled resizals */
static const int lockfullscreen = 1; /* 1 will force focus on the fullscreen window */

static const Layout layouts[] = {
    /* symbol     arrange function */
    { "[]=",      tile },    /* Standard split layout */
    { "><>",      NULL },    /* Floating window mode */
    { "[M]",      monocle }, /* Fullscreen tabbed mode */
};

/* --- Keybindings (Super Key / Mod4Mask) -------------------------------- */
#define MODKEY Mod4Mask
#define TAGKEYS(KEY,TAG) \
    { MODKEY,                       KEY,      view,           {.ui = 1 << TAG} }, \
    { MODKEY|ControlMask,           KEY,      toggleview,     {.ui = 1 << TAG} }, \
    { MODKEY|ShiftMask,             KEY,      tag,            {.ui = 1 << TAG} }, \
    { MODKEY|ControlMask|ShiftMask, KEY,      toggletag,      {.ui = 1 << TAG} },

static char dmenumon[2] = "0";
static const char *launchercmd[] = { "shree-launcher", NULL };
static const char *cmdpalette[]  = { "shree-cmdpalette", NULL };
static const char *clipboardcmd[]= { "shree-clipboard", NULL };
static const char *filescmd[]    = { "shree-files", NULL };
static const char *termcmd[]     = { "st", NULL };
static const char *shotfullcmd[] = { "shree-screenshot", "full", NULL };
static const char *shotregcmd[]  = { "shree-screenshot", "select", NULL };

static const Key keys[] = {
    /* modifier                     key        function        argument */
    { MODKEY,                       XK_space,  spawn,          {.v = launchercmd } },
    { MODKEY,                       XK_k,      spawn,          {.v = cmdpalette } },
    { MODKEY,                       XK_v,      spawn,          {.v = clipboardcmd } },
    { MODKEY,                       XK_e,      spawn,          {.v = filescmd } },
    { MODKEY,                       XK_Return, spawn,          {.v = termcmd } },
    { 0,                            XK_Print,  spawn,          {.v = shotfullcmd } },
    { MODKEY|ShiftMask,             XK_4,      spawn,          {.v = shotregcmd } },
    { MODKEY,                       XK_b,      togglebar,      {0} },
    { MODKEY,                       XK_j,      focusstack,     {.i = +1 } },
    { MODKEY,                       XK_k,      focusstack,     {.i = -1 } },
    { MODKEY,                       XK_h,      setmfact,       {.f = -0.05} },
    { MODKEY,                       XK_l,      setmfact,       {.f = +0.05} },
    { MODKEY,                       XK_Left,   setmfact,       {.f = -0.05} },
    { MODKEY,                       XK_Right,  setmfact,       {.f = +0.05} },
    { MODKEY,                       XK_Up,     setlayout,      {.v = &layouts[2]} },
    { MODKEY,                       XK_Down,   setlayout,      {.v = &layouts[0]} },
    { MODKEY,                       XK_Tab,    view,           {0} },
    { MODKEY,                       XK_q,      killclient,     {0} },
    { MODKEY,                       XK_t,      setlayout,      {.v = &layouts[0]} },
    { MODKEY,                       XK_f,      setlayout,      {.v = &layouts[1]} },
    { MODKEY,                       XK_m,      setlayout,      {.v = &layouts[2]} },
    TAGKEYS(                        XK_1,                      0)
    TAGKEYS(                        XK_2,                      1)
    TAGKEYS(                        XK_3,                      2)
    TAGKEYS(                        XK_4,                      3)
    { MODKEY|ShiftMask,             XK_q,      quit,           {0} },
};

/* --- Mouse Buttons ----------------------------------------------------- */
static const Button buttons[] = {
    /* click                event mask      button          function        argument */
    { ClkLtSymbol,          0,              Button1,        setlayout,      {0} },
    { ClkClientWin,         MODKEY,         Button1,        movemouse,      {0} },
    { ClkClientWin,         MODKEY,         Button2,        togglefloating, {0} },
    { ClkClientWin,         MODKEY,         Button3,        resizemouse,    {0} },
    { ClkTagBar,            0,              Button1,        view,           {0} },
    { ClkTagBar,            0,              Button3,        toggleview,     {0} },
};

#endif
