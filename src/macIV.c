#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <mach-o/dyld.h>
#include <sys/stat.h>
#include <limits.h>
#include <dirent.h>
#include <stdint.h>
#include <zlib.h>
#include <CoreFoundation/CoreFoundation.h>

#define GTAIV_EXE_SHA256 "3d90e7c516fa450ca002e5031e62c0f66b404590f33e6cc9793b0da4fffbfd0f"
#define PREF_DOMAIN CFSTR("io.github.awis13.liberty-pro-max")

static int file_exists(const char *path) {
    struct stat st;
    return (stat(path, &st) == 0);
}

static int has_episodes_in_dir(const char *gamedata_path) {
    char p[PATH_MAX];
    snprintf(p, sizeof(p), "%s/TLAD/setup2.xml", gamedata_path);
    if (file_exists(p)) return 1;
    snprintf(p, sizeof(p), "%s/TBoGT/setup2.xml", gamedata_path);
    if (file_exists(p)) return 1;
    return 0;
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

static CFStringRef get_pref_domain(void) {
    CFBundleRef main_bundle = CFBundleGetMainBundle();
    CFStringRef bid = main_bundle ? CFBundleGetIdentifier(main_bundle) : NULL;
    return bid ? bid : PREF_DOMAIN;
}

static void set_default_preferences(const char *folder_path, int has_episodes) {
    CFStringRef domain = get_pref_domain();
    CFStringRef key = CFSTR("GameFolder");
    CFStringRef val = CFStringCreateWithCString(kCFAllocatorDefault, folder_path, kCFStringEncodingUTF8);
    if (val) {
        CFPreferencesSetAppValue(key, val, domain);
        CFRelease(val);
    }

    // Default Anti-Aliasing to SMAA + MetalFX spatial (index 4) if not already configured
    CFPropertyListRef cur_aa = CFPreferencesCopyAppValue(CFSTR("AntiAliasing"), domain);
    if (!cur_aa) {
        int default_aa = 4;
        CFNumberRef aa_num = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &default_aa);
        if (aa_num) {
            CFPreferencesSetAppValue(CFSTR("AntiAliasing"), aa_num, domain);
            CFRelease(aa_num);
        }
    } else {
        CFRelease(cur_aa);
    }

    // Enable Complete Edition DLC episodes (TLAD / TBoGT) automatically if present and not explicitly overridden
    if (has_episodes) {
        CFPropertyListRef cur_ep = CFPreferencesCopyAppValue(CFSTR("Episodes"), domain);
        if (!cur_ep) {
            CFPreferencesSetAppValue(CFSTR("Episodes"), kCFBooleanTrue, domain);
            // Prevent Liberty Pro Max's one-time ClearedOnce migration from stripping Episodes on first run
            CFPropertyListRef cur_sco = CFPreferencesCopyAppValue(CFSTR("StoredChangesOnly"), domain);
            if (!cur_sco) {
                CFPreferencesSetAppValue(CFSTR("StoredChangesOnly"), kCFBooleanTrue, domain);
            } else {
                CFRelease(cur_sco);
            }
        } else {
            CFRelease(cur_ep);
        }
    }

    CFPreferencesAppSynchronize(domain);
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

static void repair_save_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return;
    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (fsize < 272) { fclose(f); return; }

    uint8_t *buf = (uint8_t *)malloc((size_t)fsize + 32);
    if (!buf) { fclose(f); return; }
    if (fread(buf, 1, (size_t)fsize, f) != (size_t)fsize) {
        free(buf); fclose(f); return;
    }
    fclose(f);

    // Verify GTA IV save marker b"SAVE" at offset 12..15
    if (memcmp(buf + 12, "SAVE", 4) != 0) {
        free(buf); return;
    }

    // Locate "END\0" terminator from end of file
    long end_pos = -1;
    for (long i = fsize - 4; i >= 272; i--) {
        if (buf[i] == 'E' && buf[i+1] == 'N' && buf[i+2] == 'D' && buf[i+3] == 0) {
            end_pos = i;
            break;
        }
    }
    if (end_pos < 0) {
        free(buf); return;
    }

    size_t inner_len = (size_t)end_pos + 4;
    size_t target_size = inner_len + 12;

    // Compute standard CRC32 over inner save data (offset 16 up to END\0)
    uLong crc = crc32(0L, Z_NULL, 0);
    crc = crc32(crc, (const Bytef *)(buf + 16), (uInt)(inner_len - 16));
    uint32_t expected_crc = (uint32_t)crc;

    uint32_t current_hdr_size = *(uint32_t *)(buf + 4);
    int needs_repair = 0;

    if ((size_t)fsize != target_size) {
        needs_repair = 1;
    } else {
        uint32_t current_crc = *(uint32_t *)(buf + inner_len);
        if (current_crc != expected_crc || current_hdr_size != (uint32_t)target_size) {
            needs_repair = 1;
        }
    }

    if (needs_repair) {
        // Backup original save file to .bak before modification
        char bak[PATH_MAX];
        snprintf(bak, sizeof(bak), "%s.bak", path);
        struct stat st;
        if (stat(bak, &st) != 0) {
            FILE *bf = fopen(bak, "wb");
            if (bf) {
                fwrite(buf, 1, (size_t)fsize, bf);
                fclose(bf);
            }
        }

        // Correct header file size
        *(uint32_t *)(buf + 4) = (uint32_t)target_size;

        // Append 12-byte XLive container footer: [CRC32 (4B)][0xCDCDCDCD (4B)][imag (4B)]
        *(uint32_t *)(buf + inner_len) = expected_crc;
        *(uint32_t *)(buf + inner_len + 4) = 0xCDCDCDCD;
        memcpy(buf + inner_len + 8, "imag", 4);

        FILE *wf = fopen(path, "wb");
        if (wf) {
            fwrite(buf, 1, target_size, wf);
            fclose(wf);
            fprintf(stderr, "macIV: Repaired savegame %s (size %ld -> %zu, CRC 0x%08X)\n",
                    path, fsize, target_size, expected_crc);
        }
    }

    free(buf);
}

static void repair_save_games(void) {
    const char *home = getenv("HOME");
    if (!home) return;

    char saves_dir[PATH_MAX];
    snprintf(saves_dir, sizeof(saves_dir),
             "%s/Library/Application Support/gtaiv/drive_c/Documents and Settings/Player/Local Settings/Application Data/Rockstar Games/GTA IV/savegames/user_ee000000deadc0de",
             home);

    DIR *d = opendir(saves_dir);
    if (!d) return;

    struct dirent *de;
    while ((de = readdir(d)) != NULL) {
        if (strncmp(de->d_name, "SGTA4", 5) == 0 && strlen(de->d_name) == 7 &&
            de->d_name[5] >= '0' && de->d_name[5] <= '9' &&
            de->d_name[6] >= '0' && de->d_name[6] <= '9') {
            char filepath[PATH_MAX];
            snprintf(filepath, sizeof(filepath), "%s/%s", saves_dir, de->d_name);
            repair_save_file(filepath);
        }
    }
    closedir(d);
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

    // Verify and auto-repair transferred/converted save games (fixes missing footers or CRC/size mismatches)
    repair_save_games();

    // Configure default log location if not set
    const char *home = getenv("HOME");
    if (home) {
        char default_log[PATH_MAX];
        snprintf(default_log, sizeof(default_log), "%s/Library/Logs/gtaiv.log", home);
        setenv("GTAIV_LOG", default_log, 0);
    }

    // Limit shared GPU vertex/index buffer heap to 256 MB (down from 512 MB).
    // This preserves an extra 256 MB of 32-bit guest address space for game streaming,
    // preventing RESC10 ("Out of video memory") crashes when flying or in dense scenes.
    setenv("GTAIV_GPU_HEAP_MB", "256", 0);

    // Check if game data is baked inside the bundle
    char gtaiv_exe[PATH_MAX];
    snprintf(gtaiv_exe, sizeof(gtaiv_exe), "%s/GTAIV.exe", gamedata_path);
    int has_baked_data = file_exists(gtaiv_exe);

    if (has_baked_data) {
        int has_episodes = has_episodes_in_dir(gamedata_path);
        setenv("GTAIV_GAME_DIR", gamedata_path, 1);
        setenv("RECOMP_UPSCALER", "metalfx-spatial", 0);
        if (has_episodes) {
            setenv("GTAIV_EPISODES", "1", 0);
        }
        set_default_preferences(gamedata_path, has_episodes);

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
