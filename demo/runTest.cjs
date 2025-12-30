const fs = require("fs");
const path = require("path");
const { fileURLToPath } = require("url");
const { configDotenv } = require("dotenv");
const rbxluau = require("rbxluau");
const libCoverage = require("istanbul-lib-coverage");
const libReport = require("istanbul-lib-report");
const reports = require("istanbul-reports");

configDotenv({ quiet: true });

async function main() {
    const coverageDir = path.join(__dirname, "coverage");
    const coverageFile = path.join(coverageDir, "coverage-final.json");

    // Run Luau script to generate coverage data if it doesn't exist
    const luauScript = fs.readFileSync(
        path.join(__dirname, "test.luau"),
        "utf-8"
    );
    const tempOutPath = path.join(__dirname, "temp_out.log");
    const luauExitCode = await rbxluau.executeLuau(luauScript, {
        place: path.join(__dirname, "place.rbxl"),
        out: tempOutPath,
        exit: false,
        silent: true,
    });
    if (luauExitCode !== 0) {
        console.error(`Luau script exited with code ${luauExitCode}`);
        process.exit(luauExitCode);
    }

    const output = fs.readFileSync(tempOutPath, "utf-8");
    const json = JSON.parse(output.split("__COVPATCH__")[1]);

    fs.mkdirSync(path.dirname(coverageFile), { recursive: true });
    fs.writeFileSync(coverageFile, JSON.stringify(json, null, 2));
    fs.unlinkSync(tempOutPath);

    // Read and parse coverage data
    const coverageData = JSON.parse(fs.readFileSync(coverageFile, "utf8"));
    const coverageMap = libCoverage.createCoverageMap(coverageData);

    // Create output directory if it doesn't exist
    if (!fs.existsSync(coverageDir)) {
        fs.mkdirSync(coverageDir, { recursive: true });
    }

    // Create report context
    const context = libReport.createContext({
        dir: coverageDir,
        coverageMap: coverageMap,
        defaultSummarizer: "nested",
    });

    // Generate different report formats
    const reportFormats = [
        {
            name: "html",
            description: "HTML report (open index.html in browser)",
        },
        { name: "text", description: "Text summary to console" },
        { name: "text-summary", description: "Brief text summary" },
        { name: "lcov", description: "LCOV format (for CI/CD tools)" },
        { name: "json-summary", description: "JSON summary" },
        { name: "json", description: "Detailed JSON report" },
        { name: "cobertura", description: "Cobertura XML (for Jenkins, etc.)" },
    ];

    reportFormats.forEach((format) => {
        try {
            const report = reports.create(format.name);
            report.execute(context);
        } catch (error) {
            console.log(
                `✗ ${format.name.padEnd(15)} - Failed: ${error.message}`
            );
        }
    });
}

main().catch((err) => {
    console.error("Error during coverage processing:", err);
    process.exit(1);
});
