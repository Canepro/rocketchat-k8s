def trimExcerpt(String text, int maxLines = 120, int maxChars = 20000) {
  def lines = (text ?: '').readLines()
  if (maxLines > 0 && lines.size() > maxLines) {
    lines = lines.takeRight(maxLines)
  }
  def excerpt = lines.join('\n')
  if (maxChars > 0 && excerpt.length() > maxChars) {
    excerpt = excerpt.substring(excerpt.length() - maxChars)
  }
  excerpt
}

def writeLogExcerpt(String outputPath = '.pipelinehealer-log-excerpt.txt', int maxLines = 120, int maxChars = 20000) {
  echo "PipelineHealer bridge evidence: writeLogExcerpt called (outputPath=${outputPath})"
  if (fileExists(outputPath)) {
    echo "PipelineHealer bridge evidence: excerpt file already exists at ${outputPath}; reusing."
    def existing = trimExcerpt(readFile(outputPath), maxLines, maxChars)
    if (existing?.trim()) {
      writeFile file: outputPath, text: existing
      echo "PipelineHealer bridge evidence: reused existing excerpt (${existing.length()} chars)"
      return true
    }
    echo 'PipelineHealer bridge evidence: existing excerpt file was empty after trim; falling through to rawBuild.'
  }

  try {
    echo 'PipelineHealer bridge evidence: attempting currentBuild.rawBuild.getLog()...'
    def lines = currentBuild?.rawBuild?.getLog(maxLines) ?: []
    echo "PipelineHealer bridge evidence: rawBuild.getLog returned ${lines.size()} lines"
    def excerpt = trimExcerpt(lines.join('\n'), maxLines, maxChars)
    if (!excerpt?.trim()) {
      echo 'PipelineHealer bridge evidence: Jenkins log excerpt is empty after trim'
      return false
    }
    writeFile file: outputPath, text: excerpt
    echo "PipelineHealer bridge evidence: wrote excerpt (${excerpt.length()} chars) to ${outputPath}"
    return true
  } catch (err) {
    echo "PipelineHealer bridge evidence: rawBuild.getLog() FAILED: ${err}"
    echo 'PipelineHealer bridge evidence: this is likely a Jenkins sandbox/script-security block.'
    return false
  }
}

return this
