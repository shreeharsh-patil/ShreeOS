/*
 * desktop/configs/dmenu-config.h — ShreeOS dmenu Launcher Configuration
 *
 * Centered modal launcher layout with Inter font and calm colors.
 */

#ifndef DMENU_CONFIG_H
#define DMENU_CONFIG_H

static int topbar = 1;                      /* -b  option; if 0, dmenu appears at bottom     */
static int centered = 1;                    /* -c  option; centers dmenu on screen           */
static int min_width = 540;                 /* minimum width when centered                  */

/* -fn option overrides fonts[0]; default list of fonts */
static const char *fonts[] = {
    "Inter:size=11:weight=regular:antialias=true:autohint=true",
    "monospace:size=10"
};
static const char *prompt      = "Search ShreeOS";      /* -p  option; prompt to the left of input field */

static const char *colors[SchemeLast][2] = {
    /*     fg         bg       */
    [SchemeNorm] = { "#A1A1A6", "#1C1C1E" },
    [SchemeSel]  = { "#F5F5F7", "#2878FF" },
    [SchemeOut]  = { "#000000", "#5E9BFF" },
};

/* -l option; if nonzero, dmenu uses vertical list with given number of lines */
static unsigned int lines      = 8;
static unsigned int lineheight = 28;         /* -h option; minimum height of a menu line     */

/*
 * Characters not considered part of a word while deleting words
 * for example: " /?\"&[]"
 */
static const char worddelimiters[] = " ";

/* Size of the window border */
static unsigned int border_width = 1;

#endif
