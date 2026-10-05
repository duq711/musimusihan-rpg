// Read-only live Editor review of the existing latest BuildReport. Never starts a build or changes assets.
using System;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using Newtonsoft.Json.Linq;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace MusimusihanRpg.Tools
{
    public static class LabradorBuildWarningReview
    {
        public static string Review(string expectedAppPath, string reportPath)
        {
            var build = BuildReport.GetLatestReport();
            if (build == null || Path.GetFullPath(build.summary.outputPath) != Path.GetFullPath(expectedAppPath))
                throw new InvalidOperationException("Review only the requested app's existing latest build report.");
            var warnings = build.steps.SelectMany(step => step.messages.Select(message => new { Step = step.name, Type = message.type, Text = message.content }))
                .Where(row => row.Type == LogType.Warning).ToArray();
            var errors = build.steps.SelectMany(step => step.messages).Where(message => message.type == LogType.Error || message.type == LogType.Exception || message.type == LogType.Assert).Select(message => message.content).ToArray();
            var categories = new JArray(warnings.GroupBy(row => Category(row.Text)).OrderByDescending(group => group.Count()).Select(group => new JObject
            {
                ["category"] = group.Key, ["count"] = group.Count(),
                ["unique_message_count"] = group.Select(row => row.Text.Split('\n')[0]).Distinct().Count(),
                ["examples"] = new JArray(group.GroupBy(row => row.Text.Split('\n')[0]).Take(3).Select(message => new JObject { ["count"] = message.Count(), ["text"] = message.Key }))
            }));
            var shaders = new JArray(warnings.Select(row => Regex.Match(row.Text, @"Shader warning in '([^']+)'")).Where(match => match.Success)
                .GroupBy(match => match.Groups[1].Value).OrderByDescending(group => group.Count()).Select(group => new JObject { ["shader"] = group.Key, ["count"] = group.Count() }));
            var labrador = warnings.Where(row => Regex.IsMatch(row.Text, @"labrador|Pets[/\\]Labrador|Gallop|Run\.fbx", RegexOptions.IgnoreCase)).Select(row => row.Text).ToArray();
            var result = new JObject
            {
                ["result"] = build.summary.result.ToString(), ["unity_version"] = Application.unityVersion,
                ["path"] = build.summary.outputPath, ["build_guid"] = build.summary.guid.ToString(),
                ["build_started_reported"] = build.summary.buildStartedAt.ToString("O"), ["build_ended_reported"] = build.summary.buildEndedAt.ToString("O"),
                ["build_timestamp_kind"] = build.summary.buildStartedAt.Kind.ToString(), ["reviewed_utc"] = DateTime.UtcNow.ToString("O"),
                ["summary_warnings"] = build.summary.totalWarnings, ["reviewed_warning_messages"] = warnings.Length,
                ["warning_count_matches_summary"] = warnings.Length == build.summary.totalWarnings,
                ["summary_errors"] = build.summary.totalErrors, ["error_messages"] = new JArray(errors),
                ["source"] = "Existing latest BuildReport, matched requested app path; full messages retained in the shared Editor build log",
                ["categories"] = categories, ["shader_warning_counts"] = shaders,
                ["labrador_specific_warning_count"] = labrador.Length, ["labrador_specific_warnings"] = new JArray(labrador),
                ["limitations"] = new JArray("Read-only review of the existing BuildReport; native gameplay/rendering checks are recorded separately.", "BuildReport warning counts depend on compilation/cache reuse; count differences alone do not identify new runtime failures.")
            };
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(reportPath)));
            File.WriteAllText(reportPath, result.ToString() + "\n");
            return new JObject { ["result"] = result["result"], ["reviewed_warnings"] = warnings.Length, ["summary_warnings"] = result["summary_warnings"],
                ["summary_errors"] = result["summary_errors"], ["labrador_specific_warnings"] = labrador.Length, ["report"] = reportPath }.ToString();
        }
        static string Category(string text)
        {
            if (text.Contains("Shader warning"))
            {
                if (text.Contains("signed/unsigned")) return "shader signed/unsigned conversion";
                if (text.Contains("potentially uninitialized")) return "shader potentially uninitialized value";
                if (text.Contains("integer modulus")) return "shader integer modulus performance";
                if (text.Contains("loop control variable conflicts")) return "shader loop variable shadowing";
                if (text.Contains("gradient instruction")) return "shader varying-gradient loop unroll";
                if (text.Contains("array reference cannot")) return "shader array write loop unroll";
                return "shader compiler other";
            }
            if (Regex.IsMatch(text, "mesh|vertex|vertices|skin|bone|FBX|animation|tangent|normal", RegexOptions.IgnoreCase)) return "existing mesh/import/rig";
            if (Regex.IsMatch(text, "lighting|lightmap|shader|material", RegexOptions.IgnoreCase)) return "existing lighting/material";
            return "other build warning";
        }
    }
}
