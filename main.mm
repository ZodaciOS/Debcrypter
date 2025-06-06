#include <iostream>
#include <fstream>
#include <string>
#include <filesystem>
#include <regex>
#include <cstdlib>

using namespace std;
namespace fs = std::filesystem;

#define GREEN  "\033[1;32m"
#define RED    "\033[1;31m"
#define YELLOW "\033[1;33m"
#define RESET  "\033[0m"

void printBanner() {
    cout << YELLOW << "\n🚀 Debcrypter CLI — Extract tweaks by Bundle ID\n" << RESET;
}

int main(int argc, char* argv[]) {
    printBanner();

    if (argc != 2) {
        cout << RED << "Usage: Debcrypter <bundle_id>" << RESET << endl;
        return 1;
    }

    string bundleID = argv[1];
    cout << GREEN << "🔍 Searching for: " << bundleID << RESET << endl;

    // Rootless APT list path
    string aptListDir = "/var/jb/var/lib/apt/lists";
    bool found = false;

    for (const auto& file : fs::directory_iterator(aptListDir)) {
        if (file.path().extension() == ".gz") continue;

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
                    string repoFile = file.path().filename().string();
                    size_t underscorePos = repoFile.find('_');
                    if (underscorePos == string::npos) continue;

                    string domain = repoFile.substr(0, underscorePos);
                    string fullURL = "https://" + domain + "/" + filename;

                    cout << GREEN << "📦 Found: " << pkgName << RESET << endl;
                    cout << YELLOW << "⬇️  Downloading: " << fullURL << RESET << endl;

                    string debPath = "/var/mobile/" + pkgName + ".deb";
                    string downloadCmd = "curl -L -o " + debPath + " " + fullURL;
                    system(downloadCmd.c_str());

                    string extractPath = "/var/mobile/extracted/" + pkgName;
                    fs::create_directories(extractPath);

                    string extractCmd = "dpkg-deb -x " + debPath + " " + extractPath;
                    system(extractCmd.c_str());

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
        cout << RED << "❌ Bundle ID not found in APT lists." << RESET << endl;
    }

    return 0;
}
