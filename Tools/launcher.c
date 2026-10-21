// Launcher for the nxnative Mac host, packaged as a macOS .app.
//
// The bundle's executable must be a real Mach-O binary (LaunchServices refuses to launch a bundle
// whose CFBundleExecutable is a shell script), so this tiny program sets the environment the host
// needs and execs it. The game's own code then runs natively, with Switch graphics on Metal.
#include <fcntl.h>
#include <errno.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

// Baked in when the launcher is compiled (the packaging script passes them): the Application Support
// folder (saves and log.txt) and the memory the game is told it has. The defaults are for a manual build.
#ifndef APP_SUPPORT_NAME
#define APP_SUPPORT_NAME "nxnative"
#endif
#ifndef APP_MEM_POOL
#define APP_MEM_POOL ""
#endif
#ifndef APP_MEM_RESERVE
#define APP_MEM_RESERVE ""
#endif

static void make_dirs(const char *path) {
    char buf[4096];
    snprintf(buf, sizeof buf, "%s", path);
    for (char *q = buf + 1; *q; q++) {
        if (*q == '/') { *q = 0; mkdir(buf, 0755); *q = '/'; }
    }
    mkdir(buf, 0755);
}

static void set(const char *k, const char *v) { setenv(k, v, 1); }

int main(int argc, char **argv) {
    char exe[4096];
    uint32_t size = sizeof(exe);
    if (_NSGetExecutablePath(exe, &size) != 0) {
        fprintf(stderr, "cannot locate the executable\n");
        return 1;
    }
    char real[4096];
    if (!realpath(exe, real)) snprintf(real, sizeof real, "%s", exe);

    // .../BotW Native.app/Contents/MacOS/BotW  ->  .../BotW Native.app
    char bundle[4096];
    snprintf(bundle, sizeof bundle, "%s", real);
    for (int i = 0; i < 3; i++) {
        char *slash = strrchr(bundle, '/');
        if (slash) *slash = 0;
    }

    char res[4096], sup[4096], host[4096], patched[4096], log[4096];
    snprintf(res, sizeof res, "%s/Contents/Resources", bundle);
    const char *home = getenv("HOME");
    if (!home || !*home) home = "/Users/guxiu";
    snprintf(sup, sizeof sup, "%s/Library/Application Support/" APP_SUPPORT_NAME, home);
    // The host lives in Contents/MacOS, next to this launcher: after the exec the process is still inside the
    // bundle, so macOS resolves the bundle for it and the window / the Dock entry show the app's own icon.
    // (With the host in Resources/app the process would be a bare executable and macOS would show the generic
    // "exec" icon instead of the game's.)
    snprintf(host, sizeof host, "%s/Contents/MacOS/dmhost", bundle);
    snprintf(patched, sizeof patched, "%s/patched", res);
    snprintf(log, sizeof log, "%s/log.txt", sup);

    make_dirs(sup);
    char save[4096], temp[4096];
    snprintf(save, sizeof save, "%s/save", sup);
    snprintf(temp, sizeof temp, "%s/temp", sup);
    make_dirs(save);
    make_dirs(temp);

    char romfs[4096], msl[4096], shmap[4096], fonts[4096], aoc[4096];
    snprintf(romfs, sizeof romfs, "%s/romfs", res);
    snprintf(msl, sizeof msl, "%s/msl", res);
    snprintf(shmap, sizeof shmap, "%s/dm/shader_map.tsv", res);
    snprintf(fonts, sizeof fonts, "%s/font", res);
    snprintf(aoc, sizeof aoc, "%s/aoc", res);

    set("DM_ROMFS", romfs);
    set("DM_SAVE", save);
    set("DM_TEMP", temp);
    set("DM_MSL_DIR", msl);
    set("DM_NVN_SHMAP", shmap);
    set("DM_FONT_DIR", fonts);
    set("DM_ROOT", res);
    set("DM_WINDOW", "1");
    // The guest memory: the game with the add-on content needs more heap than the Switch's application pool gives it
    // (it runs out of heap while the add-on content is being read, and the guest writes to the null pointer the allocator returned, main+0x155a7a4).
    // The values come from the game profile (app_pool / mem_reserve); env.txt can lower both on a small machine.
    if (APP_MEM_POOL[0]) set("DM_MEM_POOL", APP_MEM_POOL);
    if (APP_MEM_RESERVE[0]) set("DM_MEM_RESERVE", APP_MEM_RESERVE);
    // The add-on content (the shrines), when it is in the bundle: DM_AOC_DIR/<index>/
    { struct stat st; if (stat(aoc, &st) == 0 && S_ISDIR(st.st_mode)) set("DM_AOC_DIR", aoc); }

    // env.txt in the support folder (one KEY=VALUE per line, like the iOS app's Documents/env.txt):
    // DM_FPS_TARGET=30 (the Switch's own 30 fps), DM_KEYS=... (scripted input), ...
    char envfile[4096];
    snprintf(envfile, sizeof envfile, "%s/env.txt", sup);
    FILE *ef = fopen(envfile, "r");
    if (ef) {
        char line[1024];
        while (fgets(line, sizeof line, ef)) {
            char *s = line;
            while (*s == ' ' || *s == '\t') s++;
            if (*s == '#' || *s == '\n' || *s == '\0') continue;
            char *nl = strchr(s, '\n'); if (nl) *nl = 0;
            char *eq = strchr(s, '=');
            if (!eq) continue;
            *eq = 0;
            char *k = s, *v = eq + 1;
            size_t kl = strlen(k);
            while (kl && (k[kl - 1] == ' ' || k[kl - 1] == '\t')) k[--kl] = 0;
            if (!kl || !*v) continue;
            setenv(k, v, 1);
            fprintf(stderr, "env: %s=%s\n", k, v);
        }
        fclose(ef);
    }

    // keep the host's output in the log (the iOS app writes log.txt the same way)
    int fd = open(log, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        dup2(fd, 1);
        dup2(fd, 2);
        if (fd > 2) close(fd);
    }

    char *args[8];
    int n = 0;
    args[n++] = host;
    args[n++] = patched;
    for (int i = 1; i < argc && n < 7; i++) args[n++] = argv[i];
    args[n] = 0;
    execv(host, args);
    fprintf(stderr, "cannot run %s: %s\n", host, strerror(errno));
    return 1;
}
