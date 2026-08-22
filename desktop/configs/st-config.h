/*
 * desktop/configs/st-config.h — ShreeOS Terminal Configuration
 *
 * Clean typography, 8px padding, dark neutral palette, cool blue cursor.
 */

#ifndef ST_CONFIG_H
#define ST_CONFIG_H

static char *font = "JetBrains Mono:pixelsize=14:antialias=true:autohint=true";
static int borderpx = 12;

/* What program is execed by st depends of these precedence rules:
 * 1: program passed with -e
 * 2: scroll and/or utmp
 * 3: SHELL environment variable
 * 4: value of shell in /etc/passwd
 * 5: value of shell in config.h
 */
static char *shell = "/bin/bash";
char *utmp = NULL;
char *scroll = NULL;
char *stty_args = "stty raw pass8 nl -echo -iexten -cstopb 38400";

/* identification sequence returned in DA and DECID */
char *vtiden = "\033[?6c";

/* Kerning / character spacing */
static float cwscale = 1.0;
static float chscale = 1.0;

/* word delimiter string */
wchar_t *worddelimiters = L" `'\"()[]{}<>";

/* selection timeouts (in milliseconds) */
static unsigned int doubleclicktimeout = 300;
static unsigned int tripleclicktimeout = 600;

/* alt screens */
int allowaltscreen = 1;

/* allow certain non-interactive (insecure) window operations */
int allowwindowops = 0;

/* draw latency range in ms - from first need to draw to first draw */
static double minlatency = 8;
static double maxlatency = 33;

/* bell volume */
static int bellvolume = 0;

/* default TERM value */
char *termname = "st-256color";

/* spaces per tab */
unsigned int tabspaces = 8;

/* Terminal colors (16 color palette) */
static const char *colorname[] = {
    /* 8 normal colors */
    "#1C1C1E", /* 0: black */
    "#E54D2E", /* 1: red */
    "#30A46C", /* 2: green */
    "#F7B955", /* 3: yellow */
    "#2878FF", /* 4: blue */
    "#8E4EC6", /* 5: magenta */
    "#12A594", /* 6: cyan */
    "#A1A1A6", /* 7: white */

    /* 8 bright colors */
    "#38383A", /* 8: bright black */
    "#EC6D53", /* 9: bright red */
    "#46B880", /* 10: bright green */
    "#F8CA7B", /* 11: bright yellow */
    "#5E9BFF", /* 12: bright blue */
    "#A56DD8", /* 13: bright magenta */
    "#30C0B0", /* 14: bright cyan */
    "#F5F5F7", /* 15: bright white */

    [255] = 0,

    /* more colors can be added after 255 to use with DefaultXX */
    "#1C1C1E", /* default background */
    "#F5F5F7", /* default foreground */
    "#2878FF", /* default cursor */
    "#1C1C1E", /* cursor text */
};

/* Default colors (colorname index)
 * foreground, background, cursor, reverse cursor
 */
unsigned int defaultfg = 257;
unsigned int defaultbg = 256;
static unsigned int defaultcs = 258;
static unsigned int defaultrcs = 259;

/* Default shape of cursor
 * 2: Block ("█")
 * 4: Underline ("_")
 * 6: Bar ("|")
 */
static unsigned int cursorshape = 2;

/* thickness of underline and bar cursors */
static unsigned int cursorthickness = 2;

/* bell style */
static int bellstyle = 0;

#endif
