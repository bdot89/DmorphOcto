// Runs a Lua script for the offline tests on a PC without a Lua interpreter.
//
// It borrows a Lua 5.1 runtime from another program (OBS Studio ships one as
// lua51.dll, a LuaJIT build) and adds the Lua 5.0 names the WoW client has
// and 5.1 dropped. Lua 5.1 accepts a few things 5.0 doesn't (#, %, ...), so
// also run tools\LuaCheck or similar for those; the tests check behaviour.
//
//   LuaHost <script.lua>
//   set LUA51_DLL=<path to a 64-bit lua51.dll> to use another runtime.
using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

static class Lua {
    [DllImport("lua51", CallingConvention = CallingConvention.Cdecl)] public static extern IntPtr luaL_newstate();
    [DllImport("lua51", CallingConvention = CallingConvention.Cdecl)] public static extern void luaL_openlibs(IntPtr L);
    [DllImport("lua51", CallingConvention = CallingConvention.Cdecl)] public static extern int luaL_loadbuffer(IntPtr L, byte[] buf, UIntPtr size, string name);
    [DllImport("lua51", CallingConvention = CallingConvention.Cdecl)] public static extern int lua_pcall(IntPtr L, int nargs, int nresults, int errfunc);
    [DllImport("lua51", CallingConvention = CallingConvention.Cdecl)] public static extern IntPtr lua_tolstring(IntPtr L, int index, out UIntPtr length);
}

static class Program {
    const string DefaultDll = @"C:\Program Files\obs-studio\bin\64bit\lua51.dll";

    // Lua 5.0 names that 5.1 / LuaJIT lack, and a traceback on errors.
    const string Prelude = @"
string.gfind = string.gfind or string.gmatch
math.mod = math.mod or math.fmod
table.getn = table.getn or function(t) if type(t.n) == 'number' then return t.n end return #t end
table.setn = table.setn or function() end
io.stdout:setvbuf('no')
";

    static int Run(IntPtr L, string code, string name) {
        byte[] bytes = System.Text.Encoding.UTF8.GetBytes(code);
        int rc = Lua.luaL_loadbuffer(L, bytes, (UIntPtr)bytes.Length, name);
        if (rc == 0) rc = Lua.lua_pcall(L, 0, 0, 0);
        if (rc != 0) {
            UIntPtr length;
            IntPtr text = Lua.lua_tolstring(L, -1, out length);
            Console.Error.WriteLine(Marshal.PtrToStringUTF8(text, (int)length));
        }
        return rc;
    }

    static int Main(string[] args) {
        if (args.Length < 1) {
            Console.Error.WriteLine("usage: LuaHost <script.lua>");
            return 2;
        }
        string dll = Environment.GetEnvironmentVariable("LUA51_DLL");
        if (string.IsNullOrEmpty(dll)) dll = DefaultDll;
        if (!File.Exists(dll)) {
            Console.Error.WriteLine("No Lua runtime at " + dll + ". Install OBS Studio or set LUA51_DLL.");
            return 2;
        }
        NativeLibrary.SetDllImportResolver(Assembly.GetExecutingAssembly(), (name, assembly, path) =>
            name == "lua51" ? NativeLibrary.Load(dll) : IntPtr.Zero);
        IntPtr L = Lua.luaL_newstate();
        Lua.luaL_openlibs(L);
        if (Run(L, Prelude, "=prelude") != 0) return 2;
        string script = args[0].Replace("\\", "/");
        string runner = "local ok, err = xpcall(function() dofile('" + script + "') end, debug.traceback)\n"
            + "if not ok then error(err, 0) end";
        return Run(L, runner, "=" + script) == 0 ? 0 : 1;
    }
}
