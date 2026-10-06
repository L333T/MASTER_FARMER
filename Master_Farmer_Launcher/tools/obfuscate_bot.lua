-- Prometheus config for bot code (tools/build_plugins.py --preset Bot).
-- Like the built-in "Medium" preset but WITHOUT Vmify (runs code in an
-- emulated VM - far too slow for per-frame bot logic) and WITHOUT AntiTamper
-- (relies on the debug library, which the Sylvanas sandbox may not expose).
return {
    LuaVersion = "Lua51",
    VarNamePrefix = "",
    NameGenerator = "MangledShuffled",
    PrettyPrint = false,
    Seed = 0,
    Steps = {
        { Name = "EncryptStrings", Settings = {} },
        {
            Name = "ConstantArray",
            Settings = {
                Threshold = 1,
                StringsOnly = true,
                Shuffle = true,
                Rotate = true,
                LocalWrapperThreshold = 0,
            },
        },
        { Name = "NumbersToExpressions", Settings = {} },
        { Name = "WrapInFunction", Settings = {} },
    },
}
