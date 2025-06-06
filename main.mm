#include <iostream>
#include <fstream>
#include <string>
#include <unordered_map>
#include <filesystem>
#include <spawn.h>
#include <sys/wait.h>

using namespace std;
namespace fs = std::filesystem;

extern char **environ;

#define GREEN  "\033[1;32m"
#define RED    "\033[1;31m"
#define YELLOW "\033[1;33m"
#define BLUE   "\033[1;34m"
#define RESET  "\033[0m"

const string VERSION = "v1.0";
const string AUTHOR = "ZodaciOS";

int run(const std::string& cmd) {
    pid_t pid;
    const char* argv[] = {"/bin/sh", "-c", cmd.c_str(), NULL};
    int status = 0;
    if (posix_spawn(&pid, "/bin/sh", NULL, NULL, (char**)argv, environ) == 0) {
        waitpid(pid, &status, 0);
    } else {
        cerr << RED << "❌ Failed to spawn command: " << cmd << RESET << endl;
        return -1;
    }
    return status;
}

unordered_map<string, string> loadRepoBaseURLs(const string& sourcesDir) {
    unordered_map<string, string> map;
    for (const auto& file : fs::directory_iterator(sourcesDir)) {
        ifstream in(file.path());
        string line;
        while (getline(in, line)) {
            if (line.rfind("deb ", 0) == 0) {
                auto parts = line.substr(4);
                size_t space = parts.find(' ');
                if (space == string::npos) continue;
                string url = parts.substr(0, space);
                string domain = url;
                if (domain.rfind("http://", 0) == 0) domain = domain.substr(7);
                if (domain.rfind("https://", 0) == 0) domain = domain.substr(8);
                if (domain.back() == '/') domain.pop_back();
                map[domain] = url;
            }
        }
    }
    return map;
}

void listInstalledPackages() {
    cout << YELLOW << "\n📦 Installed Packages:\n" << RESET;
    run("dpkg-query -W -f='${Package}\n'");
    cout << endl;
}

void listInstalledRepos() {
    cout << BLUE << "\n🌐 Installed Repos:\n" << RESET;
    for (const auto& file : fs::directory_iterator("/var/jb/etc/apt/sources.list.d")) {
        ifstream in(file.path());
        string line;
        while (getline(in, line)) {
            if (line.rfind("deb ", 0) == 0) {
                string url = line.substr(4);
                size_t space = url.find(' ');
                if (space != string::npos)
                    url = url.substr(0, space);
                cout << " - " << url << endl;
            }
        }
    }
    cout << endl;
}

void searchPackage(const string& query) {
    cout << GREEN << "\n🔍 Search results for \"" << query << "\":\n" << RESET;
    run("dpkg-query -W -f='${Package}\n' | grep " + query);
    cout << endl;
}

void respring() {
    cout << YELLOW << "\n🔁 Respringing..." << RESET << endl;
    run("killall backboardd");
}

void userspaceReboot() {
    cout << YELLOW << "\n♻️  Userspace rebooting..." << RESET << endl;
    run("ldrestart");
}

void enableVerboseLogs() {
    ofstream out("/var/mobile/.debcrypter_verbose");
    out << "true\n";
    out.close();
    cout << GREEN << "✅ Verbose logs enabled." << RESET << endl;
}

void showCredits() {
    cout << BLUE << "\n🛠 Made by ZodaciOS\n";
    cout << "🌐 GitHub: https://github.com/ZodaciOS\n" << RESET << endl;
}

void moreMenu() {
    while (true) {
        cout << BLUE << "\n🔧 More Options:\n" << RESET;
        cout << " [1] 🔁 Respring\n";
        cout << " [2] ♻️  Userspace Reboot\n";
        cout << " [3] 🐛 Enable Verbose Logs\n";
        cout << " [4] 🔙 Back to Main Menu\n";
        cout << " [5] 👤 Credits\n";
        cout << "\nSelect an option: ";

        int mChoice;
        cin >> mChoice;
        cin.ignore();

        if (mChoice == 1) {
            respring();
        } else if (mChoice == 2) {
            userspaceReboot();
        } else if (mChoice == 3) {
            enableVerboseLogs();
        } else if (mChoice == 4) {
            break;
        } else if (mChoice == 5) {
            showCredits();
        } else {
            cout << RED << "❌ Invalid choice in More Menu." << RESET << endl;
        }
    }
}

void extractPackage(const string& bundleID) {
    const string aptListDir = "/var/jb/var/lib/apt/lists";
    const string sourcesDir = "/var/jb/etc/apt/sources.list.d";

    auto repoMap = loadRepoBaseURLs(sourcesDir);
    bool found = false;

    for (const auto& file : fs::directory_iterator(aptListDir)) {
        if (file.path().extension() == ".gz") continue;

        string listFile = file.path().filename().string();
        size_t underscorePos = listFile.find('_');
        if (underscorePos == string::npos) continue;

        string domainKey = listFile.substr(0, underscorePos);
        auto baseIt = repoMap.find(domainKey);
        if (baseIt == repoMap.end()) continue;

        string baseURL = baseIt->second;
        ifstream infile(file.path());
        string line, pkgName, filename;

        while (getline(infile, line)) {
            if (line.rfind("Package:", 0) == 0) {
                pkgName = line.substr(8);
                pkgName.erase(0, pkgName.find_first_not_of(" \t"));
            }

            if (line.rfind("Filename:", 0) == 0) {
                filename = line.substr(9);
                filename.erase(0, filename.find_first_not_of(" \t"));
            }

            if (line.empty() && !pkgName.empty() && !filename.empty()) {
                if (pkgName == bundleID) {
                    string debURL = baseURL;
                    if (debURL.back() != '/') debURL += "/";
                    debURL += filename;

                    cout << GREEN << "\n📦 Found: " << pkgName << RESET << endl;
                    cout << YELLOW << "⬇️  Downloading: " << debURL << RESET << endl;

                    string debPath = "/var/mobile/" + pkgName + ".deb";
                    string wgetCmd = "/var/jb/usr/bin/wget -O \"" + debPath + "\" \"" + debURL + "\"";
                    if (run(wgetCmd) != 0) {
                        cerr << RED << "❌ wget failed. URL may be invalid or repo offline." << RESET << endl;
                        return;
                    }

                    string extractPath = "/var/mobile/extracted/" + pkgName;
                    fs::create_directories(extractPath);

                    string extractCmd = "dpkg-deb -x \"" + debPath + "\" \"" + extractPath + "\"";
                    if (run(extractCmd) != 0) {
                        cerr << RED << "❌ dpkg-deb failed. Is the .deb valid?" << RESET << endl;
                        return;
                    }

                    cout << GREEN << "✅ Extracted to: " << extractPath << RESET << endl;
                    found = true;
                    break;
                }

                pkgName.clear();
                filename.clear();
            }
        }

        if (found) break;
    }

    if (!found) {
        cout << RED << "❌ Package not found in any repo." << RESET << endl;
    }
}

void printMenu() {
    cout << YELLOW << "\n🚀 Debcrypter " << VERSION << " by " << AUTHOR << "\n" << RESET;
    cout << " [1] 🔓 Decrypt Package by Name\n";
    cout << " [2] 📦 Show Installed Package Names\n";
    cout << " [3] 🌐 Show Installed Repos\n";
    cout << " [4] 🔍 Search Installed Package\n";
    cout << " [5] ❌ Exit\n";
    cout << " [6] ⚙️  More\n";
    cout << "\nSelect an option: ";
}

int main() {
    while (true) {
        printMenu();

        int choice;
        cin >> choice;
        cin.ignore();

        if (choice == 1) {
            cout << GREEN << "Enter package name (e.g., com.example.tweak): " << RESET;
            string id;
            getline(cin, id);
            extractPackage(id);
        } else if (choice == 2) {
            listInstalledPackages();
        } else if (choice == 3) {
            listInstalledRepos();
        } else if (choice == 4) {
            cout << GREEN << "Enter search query: " << RESET;
            string query;
            getline(cin, query);
            searchPackage(query);
        } else if (choice == 5) {
            cout << BLUE << "👋 Exiting Debcrypter.\n" << RESET;
            break;
        } else if (choice == 6) {
            moreMenu();
        } else {
            cout << RED << "❌ Invalid selection. Try again." << RESET << endl;
        }
    }

    return 0;
}