/*
 * desktop/configs/dmenu-config.h — ShreeOS Spotlight-style menu configuration
 */
#ifndef DMENU_CONFIG_H
#define DMENU_CONFIG_H

static int topbar = 1;
static int centered = 0;                     /* -c enables the centered Spotlight surface */
static int min_width = 640;
static const float menu_height_ratio = 3.4f;/* Spotlight sits above vertical center */

static const char *fonts[] = {
    "Inter:size=11:weight=medium:antialias=true:autohint=true",
    "monospace:size=10"
};
static const char *prompt = "Search ShreeOS";

static const char *colors[SchemeLast][2] = {
    /*     fg         bg       */
    [SchemeNorm] = { "#A1A1A6", "#1C1C1E" },
    [SchemeSel]  = { "#F5F5F7", "#2878FF" },
    [SchemeOut]  = { "#000000", "#5E9BFF" },
};

static unsigned int lines = 8;
static const char worddelimiters[] = " ";

#endif
