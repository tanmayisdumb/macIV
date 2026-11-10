#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <mach-o/dyld.h>
#include <sys/stat.h>
#include <limits.h>
#include <CoreFoundation/CoreFoundation.h>

#define GTAIV_EXE_SHA256 "3d90e7c516fa450ca002e5031e62c0f66b404590f33e6cc9793b0da4fffbfd0f"
#define PREF_DOMAIN CFSTR("io.github.awis13.liberty-pro-max")

static int file_exists(const char *path) {
    struct stat st;
    return (stat(path, &st) == 0);
}

static void mkdir_p(const char *path) {
    char tmp[PATH_MAX];
    char *p = NULL;
    snprintf(tmp, sizeof(tmp), "%s", path);
    size_t len = strlen(tmp);
    if (len > 0 && tmp[len - 1] == '/') tmp[len - 1] = 0;
    for (p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            mkdir(tmp, 0755);
            *p = '/';
        }
    }
    mkdir(tmp, 0755);
}

static void set_default_preferences(const char *folder_path) {
    CFStringRef key = CFSTR("GameFolder");
    CFStringRef val = CFStringCreateWithCString(kCFAllocatorDefault, folder_path, kCFStringEncodingUTF8);
    if (val) {
        CFPreferencesSetAppValue(key, val, PREF_DOMAIN);
        CFRelease(val);
    }

    // Default Anti-Aliasing to SMAA + MetalFX spatial (index 4) if not already configured
    CFPropertyListRef cur_aa = CFPreferencesCopyAppValue(CFSTR("AntiAliasing"), PREF_DOMAIN);
    if (!cur_aa) {
        int default_aa = 4;
        CFNumberRef aa_num = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &default_aa);
        if (aa_num) {
            CFPreferencesSetAppValue(CFSTR("AntiAliasing"), aa_num, PREF_DOMAIN);
            CFRelease(aa_num);
        }
    } else {
        CFRelease(cur_aa);
    }

    CFPreferencesAppSynchronize(PREF_DOMAIN);
}

static void ensure_user_directories(void) {
    const char *home = getenv("HOME");
    if (!home) return;

    char app_support[PATH_MAX];
    snprintf(app_support, sizeof(app_support), "%s/Library/Application Support/gtaiv", home);
    mkdir_p(app_support);

    char logs_dir[PATH_MAX];
    snprintf(logs_dir, sizeof(logs_dir), "%s/Library/Logs", home);
    mkdir_p(logs_dir);
}

int main(int argc, char *argv[]) {
    // 1. Resolve application bundle paths
    char exec_path[PATH_MAX];
    uint32_t size = sizeof(exec_path);
    if (_NSGetExecutablePath(exec_path, &size) != 0) {
        fprintf(stderr, "macIV: Unable to locate executable path.\n");
        return 1;
    }

    char real_exec[PATH_MAX];
    if (!realpath(exec_path, real_exec)) {
        strncpy(real_exec, exec_path, sizeof(real_exec) - 1);
        real_exec[sizeof(real_exec) - 1] = '\0';
    }

    // real_exec is ".../Contents/MacOS/macIV"
    char *last_slash = strrchr(real_exec, '/');
    if (!last_slash) return 1;
    *last_slash = '\0'; // real_exec is now ".../Contents/MacOS"

    char contents_dir[PATH_MAX];
    strncpy(contents_dir, real_exec, sizeof(contents_dir) - 1);
    contents_dir[sizeof(contents_dir) - 1] = '\0';
    char *c_slash = strrchr(contents_dir, '/');
    if (!c_slash) return 1;
    *c_slash = '\0'; // contents_dir is now ".../Contents"

    char engine_path[PATH_MAX];
    snprintf(engine_path, sizeof(engine_path), "%s/gtaiv", real_exec);

    char gamedata_path[PATH_MAX];
    snprintf(gamedata_path, sizeof(gamedata_path), "%s/Resources/GameData", contents_dir);

    // Ensure save & log directories exist
    ensure_user_directories();

    // Configure default log location if not set
    const char *home = getenv("HOME");
    if (home) {
        char default_log[PATH_MAX];
        snprintf(default_log, sizeof(default_log), "%s/Library/Logs/gtaiv.log", home);
        setenv("GTAIV_LOG", default_log, 0);
    }

    // Check if game data is baked inside the bundle
    char gtaiv_exe[PATH_MAX];
    snprintf(gtaiv_exe, sizeof(gtaiv_exe), "%s/GTAIV.exe", gamedata_path);
    int has_baked_data = file_exists(gtaiv_exe);

    if (has_baked_data) {
        setenv("GTAIV_GAME_DIR", gamedata_path, 1);
        setenv("RECOMP_UPSCALER", "metalfx-spatial", 0);
        set_default_preferences(gamedata_path);

        // Ensure commandline.txt exists with default modern memory settings (-norestrictions, -nomemrestrict, -availablevidmem 2047)
        char cmdline_path[PATH_MAX];
        snprintf(cmdline_path, sizeof(cmdline_path), "%s/commandline.txt", gamedata_path);
        if (!file_exists(cmdline_path)) {
            FILE *cf = fopen(cmdline_path, "w");
            if (cf) {
                fputs("-norestrictions\n-nomemrestrict\n-availablevidmem 2047\n", cf);
                fclose(cf);
            }
        }
    }

    // Check if the engine binary exists
    if (!file_exists(engine_path)) {
        fprintf(stderr, "macIV: Engine binary not found at %s\n", engine_path);
        // Show native alert explaining the quick install requirement
        char alert_cmd[PATH_MAX * 2];
        snprintf(alert_cmd, sizeof(alert_cmd),
                 "osascript -e 'display alert \"Grand Theft Auto IV: Build Required\" "
                 "message \"To play GTA IV natively on Apple Silicon, your GTAIV.exe files must be built into the native bundle.\\n\\n"
                 "Please run the one-line quick-install:\\n"
                 "curl -fsSL https://raw.githubusercontent.com/tanmayisdumb/macIV/main/quick-install.sh | bash\" "
                 "as critical'");
        system(alert_cmd);
        return 1;
    }

    // If game data is baked inside the bundle
    if (has_baked_data) {
        chdir(gamedata_path);

        // Check if user passed arguments (excluding macOS Finder -psn parameter)
        int has_user_args = 0;
        for (int i = 1; i < argc; i++) {
            if (strncmp(argv[i], "-psn", 4) != 0) {
                has_user_args = 1;
                break;
            }
        }

        if (has_user_args) {
            // Forward arguments, prepending --game-dir
            char **new_argv = (char **)malloc((argc + 4) * sizeof(char *));
            if (!new_argv) return 1;

            int idx = 0;
            new_argv[idx++] = engine_path;
            new_argv[idx++] = "--game-dir";
            new_argv[idx++] = gamedata_path;

            for (int i = 1; i < argc; i++) {
                if (strncmp(argv[i], "-psn", 4) != 0) {
                    new_argv[idx++] = argv[i];
                }
            }
            new_argv[idx] = NULL;

            execv(engine_path, new_argv);
            free(new_argv);
        } else {
            char *new_argv[] = { engine_path, "--game-dir", gamedata_path, NULL };
            execv(engine_path, new_argv);
        }

        perror("macIV: Failed to execute gtaiv engine");
        return 1;
    }

    // If external game folder was provided via CLI
    if (argc >= 2 && strncmp(argv[1], "-psn", 4) != 0) {
        argv[0] = engine_path;
        execv(engine_path, argv);
        perror("macIV: Failed to execute gtaiv with CLI arguments");
        return 1;
    }

    // Default launch
    char *fallback_argv[] = { engine_path, NULL };
    execv(engine_path, fallback_argv);
    perror("macIV: Failed to launch gtaiv fallback");
    return 1;
}
