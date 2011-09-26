/* 
 * This file is part of the bring.out FMK, a free and open source 
 * accounting software suite,
 * Copyright (c) 1996-2011 by bring.out doo Sarajevo.
 * It is licensed to you under the Common Public Attribution License
 * version 1.0, the full text of which (including FMK specific Exhibits)
 * is available in the file LICENSE_CPAL_bring.out_FMK.md located at the 
 * root directory of this source code archive.
 * By using this software, you agree to be bound by its terms.
 */

#! /usr/bin/env ruby
#--
# PDF::Writer for Ruby.
#   http://rubyforge.org/projects/ruby-pdf/
#   Copyright 2003 - 2005 Austin Ziegler.
#
# Licensed under a MIT-style licence. See LICENCE in the main distribution
# for full licensing information.
# fmkpdf.rb - derived from textbook.rb
# bring.out.ba ernad.husremovic at sigma-com.net
#
#++

require 'pdf/simpletable'
require 'pdf/charts/stddev'
require 'yaml'

#require 'cgi'
#require 'open-uri'

begin
  require 'progressbar'
rescue LoadError
  class ProgressBar #:nodoc:
    def initialize(*args)
    end
    def method_missing(*args)
    end
  end
end

require 'optparse'
require 'ostruct'

 
class PDF::FmkPdf < PDF::Writer
  
  attr_accessor :table_of_contents
  attr_accessor :chapter_number

    # A stand-alone replacement callback that will return an internal link
    # with either the name of the cross-reference or the page on which the
    # cross-reference appears as the label. If the page number is not yet
    # known (when the cross-referenced item has not yet been rendered, e.g.,
    # forward-references), the label will be used in any case.
    #
    # The parameters are:
    # name::  The name of the cross-reference.
    # label:: Either +page+, +title+, or +text+. +page+ will <em>not</em> be
    #         used for forward references; only +title+ or +text+ will be
    #         used.
    # text::  Required if +label+ has a value of +text+. Ignored if +label+
    #         is +title+, optional if +label+ is +page+. This value will be
    #         used as the display text for the internal link. +text+
    #         takes precedence over +title+ if +label+ is +page+.
  class TagXref
    def self.[](pdf, params)
      name  = params["name"]
      item  = params["label"]
      text  = params["text"]

      xref = pdf.xref_table[name]
      if xref
        case item
        when 'page'
          label = xref[:page]
          if text.nil? or text.empty?
            label ||= xref[:title]
          else
            label ||= text
          end
        when 'title'
          label = xref[:title]
        when 'text'
          label = text
        end

        "<c:ilink dest='#{xref[:xref]}'>#{label}</c:ilink>"
      else
        warn PDF::FmkPdf::Lang[:fmkpdf_unknown_xref] % [ name ]
        PDF::FmkPdf::Lang[:fmkpdf_unknown_xref] % [ name ]
      end
    end
  end
  
  PDF::Writer::TAGS[:replace]["xref"] = PDF::FmkPdf::TagXref

  # A stand-alone callback that draws a dotted line over tao the right and
    # appends a page number. The info[:params] will be like a standard XML
    # tag with three named parameters:
    #
    # level:: The table of contents level that corresponds to a particular
    #         style. In the current FmkPdf implementation, there are only
    #         two levels. Level 1 uses a 16 point font and #level1_style;
    #         level 2 uses a 12 point font and #level2_style.
    # page::  The page number that is to be printed.
    # xref::  The target destination that will be used as a link.
    #
    # All parameters are required.
  class TagTocDots
    
    DEFAULT_L1_STYLE = {
      :width      => 1,
      :cap        => :round,
      :dash       => { :pattern => [ 1, 3 ], :phase => 1 },
      :font_size  => 16
    }

    DEFAULT_L2_STYLE = {
      :width      => 1,
      :cap        => :round,
      :dash       => { :pattern => [ 1, 5 ], :phase => 1 },
      :font_size  => 12
    }

    class << self
        # Controls the level 1 style.
      attr_accessor :level1_style
        # Controls the level 2 style.
      attr_accessor :level2_style

      def [](pdf, info)
        if @level1_style.nil?
          @level1_style = sh = DEFAULT_L1_STYLE
          ss      = PDF::Writer::StrokeStyle.new(sh[:width])
          ss.cap  = sh[:cap] if sh[:cap]
          ss.dash = sh[:dash] if sh[:dash]
          @_level1_style = ssi
        end
        if @level2_style.nil?
          @level2_style = sh = DEFAULT_L2_STYLE
          ss      = PDF::Writer::StrokeStyle.new(sh[:width])
          ss.cap  = sh[:cap] if sh[:cap]
          ss.dash = sh[:dash] if sh[:dash]
          @_level2_style = ss
        end

        level = info[:params]["level"]
        page  = info[:params]["page"]
        xref  = info[:params]["xref"]

        xpos = 520

        pdf.save_state
        case level
        when "1"
          pdf.stroke_style @_level1_style
          size = @level1_style[:font_size]
        when "2"
          pdf.stroke_style @_level2_style
          size = @level2_style[:font_size]
        end

        page = "<c:ilink dest='#{xref}'>#{page}</c:ilink>" if xref

        pdf.line(xpos, info[:y], info[:x] + 5, info[:y]).stroke
        pdf.restore_state
        pdf.add_text(xpos + 5, info[:y], page, size)
      end
    end
  end
  PDF::Writer::TAGS[:single]["tocdots"] = PDF::FmkPdf::TagTocDots

  attr_reader :xref_table
  def __build_xref_table(data)
    headings = data.grep(HEADING_FORMAT_RE)

    @xref_table = {}

    headings.each_with_index do |text, idx|
      level, label, name = HEADING_FORMAT_RE.match(text).captures

      xref = "xref#{idx}"

      name ||= idx.to_s
      @xref_table[name] = {
        :title  => __send__("__heading#{level}", label),
        :page   => nil,
        :level  => level.to_i,
        :xref   => xref
      }
    end
  end
  private :__build_xref_table

  def __render_paragraph
    unless @fmkpdf_para.empty?
      fmkpdf_text(@fmkpdf_para)
      @fmkpdf_para.replace ""
    end
  end
  private :__render_paragraph
  
  
  def __render_chunk
    unless @fmkpdf_para.empty?
      fmkpdf_chunk_text(@fmkpdf_para)
      @fmkpdf_para.replace ""
    end
  end
  private :__render_chunk
  
  #primjeri: #%FS012#'  - fontsize = 12 pointa, #%FS110#'  - fontsize = 110 pointa
  PTXT_FS_CODE_MATCH = %r{FS(\d{3})}o
  
  PTXT_PH_CODE_MATCH = %r{PH(\d{3})}o
  
  #primjeri: #%DOCNA#Ime dokumenta
  PTXT_DOCNAME_MATCH = %r{\#\%DOCNA\#(.*)}o
  
  
  # primjeri: #%INI__# #%10CPI#  #%BON__# #%BOFF_# #%PIC_H# #%UON__# #%UOFF_# #%AR100#
  PTXT_CODE_MATCH = %r{\#\%(.{5})\#}o
  
  # ptxt directive: ini
  def ptxt_directive_ini__
    
    pdf = self
    pdf.fmkpdf_encoding = encoding_852
    

    pdf.top_margin    = 24
    #pdf.bottom_margin = options[:bottom_margin] if options[:bottom_margin]

    
    __fmkpdf_set_font
   
    pdf.open_object do |footing|
     pdf.save_state
     pdf.stroke_style! PDF::Writer::StrokeStyle::DEFAULT
     pdf.stroke_color! Color::RGB::Yellow

     s = 6
     t = "http://rubyforge.org/projects/ruby-pdf"
     x = pdf.absolute_left_margin
     y = pdf.absolute_bottom_margin
     #pdf.add_text(x, y, t, s)

     x = pdf.absolute_left_margin
     w = pdf.absolute_right_margin
     #puts "debug margin #{absolute_right_margin - pdf.absolute_left_margin}" 
     y += (pdf.font_height(s) * 1.05)
     
     __add_image(pdf, 'fakt_footer.jpg', x, y)
     #pdf.line(x, y, w, y).stroke
     
     pdf.restore_state
     pdf.close_object
     pdf.add_object(footing, :all_pages)
     
    end
  end
  
  def __add_image(pdf, file, x, y) 
     image_data = open(file, "rb") { |file| file.read }
     info = info = PDF::Writer::Graphics::ImageInfo.new(image_data)
     pdf.add_image(image_data, x, y, absolute_right_margin - pdf.absolute_left_margin, nil, info)
  end
  
  private :__add_image

  # picture header, - x_height - velicina u karakterima
  def ptxt_directive_ph(x_height)
    #image "fakt_header.jpg", :justification => :center,  :width => (self.absolute_right_margin - self.absolute_left_margin)
    x = self.absolute_left_margin
    y = self.absolute_top_margin - x_height * Y_ROW_HEIGHT
    
    __add_image(self, 'fakt_header.jpg', x, y)
    while x_height > 0 do  
      @fmkpdf_para = " "
      @fmkpdf_y_spacing = 1.1
      __render_chunk
      @fmkpdf_x = 0
      @fmkpdf_y += 1 
      @fmkpdf_y_delta += Y_ROW_HEIGHT * @fmkpdf_y_spacing
      x_height -= 1
    end
    
    @fmkpdf_y_spacing = 1
  end
  

  
  def ptxt_directive_pic_f
    #image "fakt_footer.jpg",  :justification => :center 
  end
  
  # ptxt directive : set document name
  def ptxt_directive_docna(doc_name)
    #fmkpdf_directive_title(doc_name)
    @fmkpdf_current_line = ""
    
  end
  
  # ptxt directive : new page
  def ptxt_directive_nstr_
    # stavi na pending - ako nije zadnja, onda pokreni novu stranu
    @fmkpdf_nstr_pending = true 
  end
  
  # "#%10CPI#" - mono, 10
  def ptxt_directive_10cpi(left, right)
      @fmkpdf_current_line = right  
      @fmkpdf_para = left
      
      if not @fmkpdf_para.empty?
        __render_chunk
      end
      
      @fmkpdf_font_type = :mono
      @fmkpdf_font_size  = 10
  end
  
  # "#%12CPI#" - mono_2, 10
  def ptxt_directive_12cpi(left, right)
      @fmkpdf_current_line = right  
      @fmkpdf_para = left
      
      if not @fmkpdf_para.empty?
        __render_chunk
      end
      
      @fmkpdf_font_type = :mono_2
      @fmkpdf_font_size  = 10
  end
  
  # "#%KON17#" - mono, 8
  def ptxt_directive_kon17(left, right)
      @fmkpdf_current_line = right  
      @fmkpdf_para = left
      
      if not @fmkpdf_para.empty?
        __render_chunk
      end
      
      @fmkpdf_font_type = :mono_2
      @fmkpdf_font_size  = 8
  end
    
  
  # "#%KON20#", mono_2, 6
  def ptxt_directive_kon20(left, right)
     @fmkpdf_current_line = right  
      @fmkpdf_para = left
      
      if not @fmkpdf_para.empty?
        __render_chunk
     end 
  
     @fmkpdf_font_type = :mono_2
     @fmkpdf_font_size  = 6
  end

  
  def ptxt_directive_ar100(left, right)
     # za sad dummy  
    @fmkpdf_current_line = right  
    @fmkpdf_para = left
      
    if not @fmkpdf_para.empty?
        __render_chunk
    end 
  
    @fmkpdf_font_type = :mono
    @fmkpdf_font_size  = 32
  end
  
   # bold on
   def ptxt_directive_bon__ (left, right)
      
      @fmkpdf_current_line =right   
      @fmkpdf_para = left
      if not @fmkpdf_para.empty?
        __render_chunk
      end
      
      @fmkpdf_font_bold  = true
  end

  # bold off
  def ptxt_directive_boff_ (left, right)
      @fmkpdf_current_line = right  
      @fmkpdf_para = left
      
      if not @fmkpdf_para.empty?
        __render_chunk
      end
      
      @fmkpdf_font_bold  = false      
  end
  
    # italic on
   def ptxt_directive_ion__(left, right)
      @fmkpdf_current_line =right   
      @fmkpdf_para = left
      if not @fmkpdf_para.empty?
        __render_chunk
      end
      
      @fmkpdf_font_italic  = true
  end

  # italic off
  def ptxt_directive_ioff_ (left, right)    
      @fmkpdf_current_line = right  
      @fmkpdf_para = left
      
      if not @fmkpdf_para.empty?
        __render_chunk
      end
      
      @fmkpdf_font_italic  = false    
  end
  
  
  # underline on
  def ptxt_directive_uon__(left, right)
      
      @fmkpdf_current_line =right   
      @fmkpdf_para = left
      if not @fmkpdf_para.empty?
        __render_chunk
      end 
      @fmkpdf_font_underline  = true
  end

  # underline off
  def ptxt_directive_uoff_(left, right)
      
      @fmkpdf_current_line = right  
      @fmkpdf_para = left
      
      if not @fmkpdf_para.empty?
        __render_chunk
      end
      
      @fmkpdf_font_underline  = false    
  end
  
  # set font size 
  def ptxt_directive_fs(left, right, font_size)

    @fmkpdf_para = left
    @fmkpdf_current_line =right 
    
    if not @fmkpdf_para.empty?  
      __render_chunk
    end
    @fmkpdf_font_size  = font_size
    
    #if font_size > 10
    #  tmp = font_size / 11
    #  @fmkpdf_y_spacing = tmp if (tmp > @fmkpdf_y_spacing)
    #  puts " fmkpdf_y_spacing ===== {@fmkpdf_y_spacing}"
    #end
  end
  
  # procesiranje ptxt kodova 
  # left = string lijevo od koda, right = string desno od koda
  def process_ptxt_code(code, left, right)
    
    with_0_params = %r{INI__|NSTR_|PIC_F}
    if code =~ with_0_params
      res = __send__("ptxt_directive_#{code.downcase}")
      @fmkpdf_current_line=right
    elsif code =~  PTXT_FS_CODE_MATCH
      ptxt_directive_fs(left, right, $1.to_i)
    elsif code =~  PTXT_PH_CODE_MATCH
      ptxt_directive_ph($1.to_i)  
      @fmkpdf_current_line=right
    else
      res = __send__("ptxt_directive_#{code.downcase}", left, right)
    end
    
  end

  
  def process_ptxt_line(line)
  
    @fmkpdf_current_line = line
    until @fmkpdf_current_line.empty?  or !(@fmkpdf_current_line =~ PTXT_CODE_MATCH)
      @fmkpdf_current_line.sub(PTXT_CODE_MATCH, "")
      match = Regexp.last_match 
      if not match.nil?
         process_ptxt_code(match[1], match.pre_match, match.post_match)
      end
 
      
      @fmkpdf_current_line.sub(PTXT_DOCNAME_MATCH, "") 
      match = Regexp.last_match 
      if not match.nil?
         ptxt_directive_docna(match[1])  
      end
      
    end
  
    if not @fmkpdf_current_line.empty?
        @fmkpdf_para = @fmkpdf_current_line
        __render_chunk
    end   
  end
  

  LINE_DIRECTIVE_RE = %r{^\.([a-z]\w+)(?:$|\s+(.*)$)}io
  
  def fmkpdf_find_directive(line)
    directive = nil
    arguments = nil
    dmatch = LINE_DIRECTIVE_RE.match(line)
    if dmatch
      directive = dmatch.captures[0].downcase.chomp
      arguments = dmatch.captures[1]
    end
    [directive, arguments]
  end
  private :fmkpdf_find_directive

  
  H1_STYLE = {
    :background     => Color::RGB::Black,
    :foreground     => Color::RGB::White,
    :justification  => :center,
    :font_size      => 26,
    :bar            => true
  }
  H2_STYLE = {
    :background     => Color::RGB::Grey80,
    :foreground     => Color::RGB::Black,
    :justification  => :left,
    :font_size      => 18,
    :bar            => true
  }
  H3_STYLE = {
    :background     => Color::RGB::White,
    :foreground     => Color::RGB::Black,
    :justification  => :left,
    :font_size      => 18,
    :bar            => false
  }
  H4_STYLE = {
    :background     => Color::RGB::White,
    :foreground     => Color::RGB::Black,
    :justification  => :left,
    :font_size      => 14,
    :bar            => false
  }
  H5_STYLE = {
    :background     => Color::RGB::White,
    :foreground     => Color::RGB::Black,
    :justification  => :left,
    :font_size      => 12,
    :bar            => false
  }
  
  def __heading1(heading)
    @chapter_number ||= 0
    @chapter_number = @chapter_number.succ
    "#{chapter_number}. #{heading}"
  end
  def __heading2(heading)
    heading
  end
  def __heading3(heading)
    "<b>#{heading}</b>"
  end
  def __heading4(heading)
    "<i>#{heading}</i>"
  end
  def __heading5(heading)
    "<c:uline>#{heading}</c:uline>"
  end

  # .1 vako nako 
  # .2 vako nako
  HEADING_FORMAT_RE = %r{^([\d])<(.*)>([a-z\w]+)?$}o 

  def fmkpdf_heading(line)
    head = HEADING_FORMAT_RE.match(line)
    if head
      __render_paragraph

      @heading_num ||= -1
      @heading_num += 1

      level, heading, name = head.captures
      level = level.to_i

      name ||= @heading_num.to_s
      heading = @xref_table[name]

      style   = self.class.const_get("H#{level}_STYLE")

      start_transaction(:heading_level)
      ok = false

      loop do # while not ok
        break if ok
        this_page = pageset.size

        save_state

        if style[:bar]
          fill_color style[:background]
          fh = font_height(style[:font_size]) * 1.01
          fd = font_descender(style[:font_size]) * 1.01
          x = absolute_left_margin
          w = absolute_right_margin - absolute_left_margin
          rectangle(x, y - fh + fd, w, fh).fill
        end

        fill_color style[:foreground]
        text(heading[:title], :font_size => style[:font_size],
             :justification => style[:justification])

        restore_state

        if (pageset.size == this_page)
          commit_transaction(:heading_level)
          ok = true
        else
            # We have moved onto a new page. This is bad, as the background
            # colour will be on the old one.
          rewind_transaction(:heading_level)
          start_new_page
        end
      end

      heading[:page] = which_page_number(current_page_number)

      case level
      when 1, 2
        @table_of_contents << heading
      end

      add_destination(heading[:xref], 'FitH', @y + font_height(style[:font_size]))
    end
    head
  end
  private :fmkpdf_heading

  def fmkpdf_parse(document, progress = nil)
    @table_of_contents = []

    @toc_title          = "Tabela sadržaja "
    @gen_toc            = false
    @fmkpdf_code      = ""

     
    @fmkpdf_font_size  = 10
    @fmkpdf_textopt   = { :justification => :full }
    @fmkpdf_lastmode  = @fmkpdf_mode = :preserved
   

    @fmkpdf_textfont  = "Times-Roman"
    @fmkpdf_codefont  = "BringOutBaTahomaMono.afm"
    @fmkpdf_font_bold = false
    @fmkpdf_font_italic = false
    @fmkpdf_font_underline = false
    
    @fmkpdf_font_type = :mono
    @fmkpdf_font_mono_name      = "BringOutBaTahomaMono.afm"
    @fmkpdf_font_mono_2_name    = "BringOutBaTahomaMono2.afm"
    
    @fmkpdf_para         = ""
    @fmkpdf_current_line = ""
    
    @blist_info         = []

    @fmkpdf_line__    = 0

    __build_xref_table(document)

    @fmkpdf_x = 0
    @fmkpdf_y = 0
    @fmkpdf_y_delta = 0
    @fmkpdf_y_spacing = 1
    @fmkpdf_nstr_pending = false
    document.each do |line|
     
      if @fmkpdf_nstr_pending
        start_new_page  
        set_margins
        @fmkpdf_x = 0
        @fmkpdf_y = 0
        @fmkpdf_y_delta = 0
        @fmkpdf_y_spacing = 1
        @fmkpdf_nstr_pending = false
      end
      
      line = line.chomp
      @fmkpdf_line__ += 1
      process_ptxt_line(line)
      @fmkpdf_y += 1
      @fmkpdf_y_delta += Y_ROW_HEIGHT * @fmkpdf_y_spacing

      @fmkpdf_y_spacing = 1
      @fmkpdf_x = 0
     
    end
      
 
  end

  def fmkpdf_toc(progress = nil)
    insert_mode :on
    insert_position :after
    insert_page 1
    start_new_page

    style = H1_STYLE
    save_state

    if style[:bar]
      fill_color    style[:background]
      fh = font_height(style[:font_size]) * 1.01
      fd = font_descender(style[:font_size]) * 1.01
      x = absolute_left_margin
      w = absolute_right_margin - absolute_left_margin
      rectangle(x, y - fh + fd, w, fh).fill
    end

    fill_color  style[:foreground]
    text(@toc_title, :font_size => style[:font_size],
         :justification => style[:justification])

    restore_state

    self.y += font_descender(style[:font_size])#* 0.5

    right = absolute_right_margin

      # TODO -- implement tocdots as a replace tag and a single drawing tag.
    @table_of_contents.each do |entry|
      #progress.inc if progress

      info =  "<c:ilink dest='#{entry[:xref]}'>#{entry[:title]}</c:ilink>"
      info << "<C:tocdots level='#{entry[:level]}' page='#{entry[:page]}' xref='#{entry[:xref]}'/>"

      case entry[:level]
      when 1
        text info, :font_size => 16, :absolute_right => right
      when 2
        text info, :font_size => 12, :left => 50, :absolute_right => right
      end
    end
  end

  attr_accessor :fmkpdf_codefont
  attr_accessor :fmkpdf_textfont
  attr_accessor :fmkpdf_encoding
  attr_accessor :fmkpdf_font_size
  attr_accessor :fmkpdf_font_type
  attr_accessor :fmkpdf_font_bold
  attr_accessor :fmkpdf_font_underline
  attr_accessor :fmkpdf_font_italic

    # Start a new page: .newpage
  def fmkpdf_directive_newpage(args)
    __render_paragraph

    if args =~ /^force/
      start_new_page true
    else
      start_new_page
    end
  end

    # Preserved newlines: .pre
  def fmkpdf_directive_pre(args)
    __render_paragraph
    @fmkpdf_mode = :preserved
  end

    # End preserved newlines: .endpre
  def fmkpdf_directive_endpre(args)
    @fmkpdf_mode = :normal
  end

    # Code: .code
  def fmkpdf_directive_code(args)
    __render_paragraph
    select_font @fmkpdf_codefont, @fmkpdf_encoding
    @fmkpdf_lastmode, @fmkpdf_mode = @fmkpdf_mode, :normal
    @fmkpdf_textopt  = { :justification => :left, :left => 20, :right => 20 }
    @fmkpdf_font_size = 10
  end

    # End Code: .endcode
  def fmkpdf_directive_endcode(args)
    select_font @fmkpdf_textfont, @fmkpdf_encoding
    @fmkpdf_lastmode, @fmkpdf_mode = @fmkpdf_mode, @fmkpdf_lastmode
    @fmkpdf_textopt  = { :justification => :full }
    @fmkpdf_font_size = 12
  end

    # Eval: .eval
  def fmkpdf_directive_eval(args)
    __render_paragraph
    @fmkpdf_lastmode, @fmkpdf_mode = @fmkpdf_mode, :eval
  end

    # End Eval: .endeval
  def fmkpdf_directive_endeval(args)
    save_state

    thread = Thread.new do
      begin
        @fmkpdf_code.untaint
        pdf = self
        eval @fmkpdf_code
      rescue Exception => ex
        err = PDF::FmkPdf::Lang[:fmkpdf_eval_exception]
        $stderr.puts err % [ @fmkpdf_line__, ex, ex.backtrace.join("\n") ]
        raise ex
      end
    end
    thread.abort_on_exception = true
    thread.join

    restore_state
    select_font @fmkpdf_textfont, @fmkpdf_encoding

    @fmkpdf_code = ""
    @fmkpdf_mode, @fmkpdf_lastmode = @fmkpdf_lastmode, @fmkpdf_mode
  end

    # Done. Stop parsing: .done
  def fmkpdf_directive_done(args)
    unless @fmkpdf_code.empty?
      $stderr.puts PDF::FmkPdf::Lang[:fmkpdf_code_not_empty]
      $stderr.puts @fmkpdf_code
    end
    __render_paragraph
    :break
  end

    # Columns. .columns <number-of-columns>|off
  def fmkpdf_directive_columns(args)
    av = /^(\d+|off)(?: (\d+))?(?: .*)?$/o.match(args)
    unless av
      $stderr.puts PDF::FmkPdf::Lang[:fmkpdf_bad_columns_directive] % args
      raise ArgumentError
    end
    cols = av.captures[0]

      # Flush the paragraph cache.
    __render_paragraph

    if cols == "off" or cols.to_i < 2
      stop_columns
    else
      if av.captures[1]
        start_columns(cols.to_i, av.captures[1].to_i)
      else
        start_columns(cols.to_i)
      end
    end
  end

  def fmkpdf_directive_toc(args)
    @toc_title  = args unless args.empty?
    @gen_toc    = true
  end

  def fmkpdf_directive_author(args)
    info.author = args
  end
  
  def fmkpdf_directive_title(args)
    info.title  = args
  end

  def fmkpdf_directive_subject(args)
    info.subject  = args
  end

  def fmkpdf_directive_keywords(args)
    info.keywords = args
  end

  LIST_ITEM_STYLES = %w(bullet disc)

  def fmkpdf_directive_blist(args)
    __render_paragraph
    sm = /^(\w+).*$/o.match(args)
    style = sm.captures[0] if sm
    style = "bullet" unless LIST_ITEM_STYLES.include?(style)

    @blist_factor = @left_margin * 0.10 if @blist_info.empty?

    info = {
      :left_margin  => @left_margin,
      :style        => style
    }
    @blist_info << info
    @left_margin += @blist_factor

    @fmkpdf_lastmode, @fmkpdf_mode = @fmkpdf_mode, :blist if :blist != @fmkpdf_mode
  end

  def fmkpdf_directive_endblist(args)
    self.left_margin = @blist_info.pop[:left_margin]
    @fmkpdf_lastmode, @fmkpdf_mode = @fmkpdf_mode, @fmkpdf_lastmode if @blist_info.empty?
  end

  def generate_table_of_contents?
    @gen_toc
  end

  attr_accessor :fmkpdf_source_dir

  Y_ROW_HEIGHT = 11
  
  def encoding_852
    difs = { 
        0x86 => "cacute", #ć
        0x8f => "Cacute", #Ć
        0x9f => "ccaron", #č
        0xac => "Ccaron", #Č
        0xa7 => "zcaron", #ž
        0xa6 => "Zcaron", #Ž
        0xd0 => "dslash", #đ
        0xd1 => "Dslash", #Đ
        0xe7 => "scaron", #š
        0xe6 => "Scaron"  #Š
    }
    encoding = {
      :encoding => "WinAnsiEncoding" ,
      :differences => difs
    }
    
    encoding
  end
  
  
  
  def self.__yaml_config(config)
    begin
      
       if ENV["SIGMA_HOME"].nil?
         if Kernel.is_windows?
            sc_home = "c:/sigma"
         else
            #ovo radi samo za mene :)
            sc_home = "/home/hernad/fmk"
         end
       else
         sc_home = ENV["SIGMA_HOME"] 
       end 
       
       
       file = sc_home + "/fmk_pdf.yml" 
       
       file = file.gsub("\/", "\\") if Kernel.is_windows?
         
     
       puts "config fajl je " + file
       
       yaml_config = YAML.load_file( file )
     
        
       config.print_to = yaml_config ["print_to"]
       config.pdf_viewer = yaml_config ["pdf_viewer"]
       config.footer = yaml_config ["fakt_footer"]
       
    rescue Exception => err
      puts err.to_str
    end
    
  end
  
  def self.run(args)
    config = OpenStruct.new
    config.regen      = false
    config.cache      = true
    config.compressed = false
    config.print = false
    config.print_to =""
    config.pdf_viewer = ""
    
    
    
    __yaml_config(config)
        
    opts = OptionParser.new do |opt|
      opt.banner    = PDF::FmkPdf::Lang[:fmkpdf_usage_banner] % [ File.basename($0) ]
      PDF::FmkPdf::Lang[:fmkpdf_usage_banner_1].each do |ll|
        opt.separator "  #{ll}"
      end
      opt.on('-f', '--force-regen', *PDF::FmkPdf::Lang[:fmkpdf_help_force_regen]) { config.regen = true }
      opt.on('-n', '--no-cache', *PDF::FmkPdf::Lang[:fmkpdf_help_no_cache]) { config.cache = false }
      opt.on('-z', '--compress', *PDF::FmkPdf::Lang[:fmkpdf_help_compress]) { config.compressed = true }
      opt.on('-p', '--print', *PDF::FmkPdf::Lang[:fmkpdf_help_print]) { config.print = true }
      
      opt.on_tail ""
      opt.on_tail("--help", *PDF::FmkPdf::Lang[:fmkpdf_help_help]) { $stderr << opt; exit(0) }
    end
    opts.parse!(args)

    config.document = args[0]

    unless config.document
      config.document = "outf.txt"
      unless File.exist?(config.document)
        dirn = File.dirname(__FILE__)
        config.document = File.join(dirn, File.basename(config.document))
        unless File.exist?(config.document)
          dirn = File.join(dirn, "..")
          config.document = File.join(dirn, File.basename(config.document))
          unless File.exist?(config.document)
            dirn = File.join(dirn, "..")
            config.document = File.join(dirn,
                                        File.basename(config.document))
            unless File.exist?(config.document)
              $stderr.puts PDF::FmkPdf::Lang[:fmkpdf_cannot_find_document]
              exit(1)
            end
          end
        end
      end

      $stderr.puts PDF::FmkPdf::Lang[:fmkpdf_using_default_doc] % config.document
    end

    dirn = File.dirname(config.document)
    extn = File.extname(config.document)
    base = File.basename(config.document, extn)

    files = {
      :document => config.document,
      :cache    => "#{base}._mc",
      :pdf      => "#{base}.pdf"
    }

    unless config.regen
      if File.exist?(files[:cache])
        _tm_doc = File.mtime(config.document)
        _tm_prg = File.mtime(__FILE__)
        _tm_cch = File.mtime(files[:cache])
        
          # If the cached file is newer than either the document or the
          # class program, then regenerate.
        if (_tm_doc < _tm_cch) and (_tm_prg < _tm_cch)
          $stderr.puts PDF::FmkPdf::Lang[:fmkpdf_using_cached_doc] % File.basename(files[:cache])
          pdf = File.open(files[:cache], "rb") { |cf| Marshal.load(cf.read) }
          pdf.save_as(files[:pdf])
          File.open(files[:pdf], "wb") { |pf| pf.write pdf.render }
          exit(0)
        else
          $stderr.puts PDF::FmkPdf::Lang[:fmkpdf_regenerating]
        end
      end
    else
      $stderr.puts PDF::FmkPdf::Lang[:fmkpdf_ignoring_cache] if File.exist?(files[:cache])
    end

    # pdf object.
    pdf = PDF::FmkPdf.new  :paper => "A4"
    
    #,  :left_margin => cm2pts(1.5), \
    #       :right_margin => cm2pts(1.2), :top_margin => cm2pts(3), :bottom_margin => cm2pts(0.9) })
    

    pdf.set_margins
     
  
            
    #self.margins_cm(1, 1.5, 1, 1.2))
    pdf.compressed = config.compressed
    pdf.fmkpdf_source_dir = File.expand_path(dirn)

    document = open(files[:document]) { |io| io.read.split($/) }
    
    progress = nil
    #progress = ProgressBar.new(base.capitalize, document.size)
      pdf.fmkpdf_parse(document, progress)  
    #progress.finish

    if pdf.generate_table_of_contents?
      progress = ProgressBar.new("TOC", pdf.table_of_contents.size)
      pdf.fmkpdf_toc(progress)
      progress.finish
    end

    if config.cache
      File.open(files[:cache], "wb") { |f| f.write Marshal.dump(pdf) }
    end

    pdf.save_as(files[:pdf])
    
    puts config.pdf_viewer  + " " + files[:pdf]
    
    system( config.pdf_viewer  + " " + files[:pdf])
  end


  def set_margins
    
    self.top_margin=cm2pts(1.2)
    self.bottom_margin=cm2pts(1.2)
    
    self.left_margin=cm2pts(1.6)
    self.right_margin=cm2pts(1.2)
  end
  

  
  def __fmkpdf_set_font
    if @fmkpdf_font_type == :mono
      fn = @fmkpdf_font_mono_name
    else @fmkpdf_font_type == :mono_2
      fn = @fmkpdf_font_mono_2_name
    end
    if @fmkpdf_font_bold
      fn = fn.sub(/\.afm/, "Bold.afm") 
    end

    self.font_size = @fmkpdf_font_size
    select_font fn, @fmkpdf_encoding
    

  end
  private :__fmkpdf_set_font
  
  def fmkpdf_chunk_text(chunk)
    __fmkpdf_set_font
    add_text(absolute_left_margin +  @fmkpdf_x, (absolute_top_margin - @fmkpdf_y_delta) , chunk) 
    @fmkpdf_x += text_width(chunk)
  end
  
  def fmkpdf_text(line)
    opt = @fmkpdf_textopt.dup
    opt[:font_size] = @fmkpdf_font_size
    text(line, opt)
  end

  instance_methods.grep(/^fmkpdf_directive_/).each do |mname|
    private mname.intern
  end
  
end

def Kernel.is_windows?
  processor, platform, *rest = RUBY_PLATFORM.split("-")
  platform == 'mswin32'
end



