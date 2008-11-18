module PDF::FmkPdf::Lang
  @message = {}

  class << self

    attr_accessor :language
    def language=(ll) #:nodoc:
      @language = ll
      @message.replace ll.instance_variable_get('@message')
    end

      # Looks up the mesasge
    def [](message_id)
      @message[message_id]
    end
  end
end


module PDF::FmkPdf::Lang::EN
  @message = { 
    :fmkpdf_bad_columns_directive => "Invalid argument to directive .columns: %s",
    :fmkpdf_cannot_find_document  => "Error: cannot find a document.",
    :fmkpdf_using_default_doc     => "Using default document '%s'.",
    :fmkpdf_using_cached_doc      => "Using cached document '%s'...",
    :fmkpdf_regenerating          => "Cached document is older than source document. Regenerating.",
    :fmkpdf_ignoring_cache        => "Ignoring cached document.",
    :fmkpdf_unknown_xref          => "Unknown cross-reference %s.",
    :fmkpdf_code_not_empty        => "Code is not empty:",
    :fmkpdf_usage_banner          => "Usage: %s [options] [INPUT FILE]",
    :fmkpdf_usage_banner_1        => [
      "INPUT FILE, if not specified, will be 'manual.pwd', either in the",
      "current directory or relative to this file.",
      ""
    ],
    :fmkpdf_help_force_regen      => [
      "Forces the regeneration of the document,",
      "ignoring the cached document version."
    ],
    :fmkpdf_help_no_cache         => [
      "Disables generated document caching.",
    ],
    :fmkpdf_help_compress         => [
      "Compresses the resulting PDF.",
    ],
    
    :fmkpdf_help_print     => [
      "Print odmah (bez pregleda PDF viewer-u).",
    ],
    
    :fmkpdf_help_help             => [
      "Shows this text.",
    ],
    :fmkpdf_exception             => "Exception %1s around line %2d.",

  }

  PDF::FmkPdf::Lang.language = self
end
