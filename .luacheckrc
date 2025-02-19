
self = false
-- Unused variables configuration
unused = true         -- Enable unused variable checking
unused_args = false   -- Don't report unused function arguments
unused_secondaries = false  -- Report unused variables in multiple assignments (a, b = 1, 2)
global = false
allow_defined_top = true
max_line_length = false
codes = true

-- Ideally reenable these warnings later
redefined = false     -- Allow variable redefinition

ignore = {
    "512", -- Loop can be executed at most once.

    "542", -- TODO: empty if branch
    "611", -- TODO: line contains only whitespace
    "612", -- TODO: line contains trailing whitespace
    "614", -- TODO: trailing whitespace in a comment
    "621", -- TODO: inconsistent indentation
}
-- Something to think about in the future
-- max_cyclomatic_complexity = 30


-- Default is probably fine, but anyway
std=lua51

globals = {
    -- std extensions
    "math.round", "math.bit_or", "math.diag", "math.cross_product", "math.triangulate",
    "table.ifind", "table.show", "table.save", "table.echo", "table.print",
    -- Spring
    "Spring", "VFS", "gl", "GL", "Game",
    "UnitDefs", "UnitDefNames", "FeatureDefs", "FeatureDefNames",
    "WeaponDefs", "WeaponDefNames", "LOG", "KEYSYMS", "CMD", "Script",
    "SendToUnsynced", "Platform", "Engine", "include", "COB",
    -- GL
    "GL_TEXTURE_2D", "GL_HINT_BIT",
    -- Gadgets
    "GG", "gadgetHandler", "gadget",
    -- Widgets
    "WG", "widgetHandler", "widget", "LUAUI_DIRNAME", "self",
    -- Chili
    "Chili", "Checkbox", "Control", "ComboBox", "Button", "Label",
    "Line", "EditBox", "Font", "Window", "ScrollPanel", "LayoutPanel",
    "Panel", "StackPanel", "Grid", "TextBox", "Image", "TreeView", "Trackbar",
    "DetachableTabPanel", "screen0", "Progressbar",
    -- Libs
    -- "LCS", "Path", "Table", "Log", "String", "Shaders", "Time", "Array", "StartScript",

    "CMDTYPE", "COBSCALE", "CallAsTeam", "SYNCED", "loadlib",
}

-- Exclude third-party modules directory if needed
exclude_files = {
    -- "third_party/*",
    -- "vendor/*",
}
