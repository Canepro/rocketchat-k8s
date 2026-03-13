def writeLogExcerpt(String outputPath = '.pipelinehealer-log-excerpt.txt', int maxLines = 120, int maxChars = 20000) {
  echo "PipelineHealer bridge evidence: writeLogExcerpt called (outputPath=${outputPath})"

  if (fileExists(outputPath)) {
    def existing = readFile(outputPath).trim()
    if (existing) {
      echo "PipelineHealer bridge evidence: reusing existing excerpt (${existing.length()} chars)"
      return true
    }
  }

  echo 'PipelineHealer bridge evidence: fetching console text via BUILD_URL API...'
  def status = sh(returnStatus: true, script: """
    set +e
    CONSOLE_URL="\${BUILD_URL}consoleText"
    EXCERPT_FILE='${outputPath}'
    EXCERPT_TMP="\${EXCERPT_FILE}.tmp"

    HTTP_CODE=\$(curl -sSo "\$EXCERPT_TMP" -w '%{http_code}' "\$CONSOLE_URL" 2>/dev/null)

    if [ "\$HTTP_CODE" = "200" ] && [ -s "\$EXCERPT_TMP" ]; then
      tail -n ${maxLines} "\$EXCERPT_TMP" | tail -c ${maxChars} > "\$EXCERPT_FILE"
      rm -f "\$EXCERPT_TMP"
      BYTES=\$(wc -c < "\$EXCERPT_FILE")
      echo "PipelineHealer bridge evidence: captured \${BYTES} bytes via consoleText API"
      exit 0
    fi

    rm -f "\$EXCERPT_TMP"
    echo "PipelineHealer bridge evidence: consoleText API returned HTTP \$HTTP_CODE"
    exit 1
  """)

  if (status == 0) {
    return true
  }

  echo 'PipelineHealer bridge evidence: all excerpt capture methods failed.'
  return false
}

return this
