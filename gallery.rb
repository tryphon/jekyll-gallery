begin; require 'exifr'; rescue LoadError; end
begin; require 'RMagick'; rescue LoadError; end

# core extensions
# ------------------------------------------------------------------------------
class Dir
    # Calls a block for each *non-hidden* file in a directory, recursivly.
    #
    def self.foreach_r(dir, &block)
        foreach(dir) do |file|
            next if file[0] == '.'

            path = File.join(dir, file)
            next if File.symlink? path

            if File.directory? path
                foreach_r(path, &block)
            else
                yield dir, file
            end
        end
    end
end

class Hash
  def deep_merge(other_hash)
    dup.deep_merge!(other_hash)
  end

  def deep_merge!(other_hash)
    other_hash.each_pair do |k,v|
      tv = self[k]
      self[k] = tv.is_a?(Hash) && v.is_a?(Hash) ? tv.deep_merge(v) : v
    end
    self
  end
end unless Hash.respond_to?(:deep_merge)

# odie gallery plugin
# ------------------------------------------------------------------------------
module Jekyll

class Site
    # Add a new array to contain all the items in the gallery
    #
    attr_accessor :gallery
end

class GalleryPost < Post
    attr_reader :name
    attr_accessor :image
    attr_accessor :image_url
    attr_accessor :image_info

    # Initialize this GalleryPost instance.
    #   +site+ is the Site
    #   +base+ is the String path to the root dir of all the galleries
    #   +source+ is the String path to the dir containing the image
    #   +categories+ is the String filename of the image
    #
    # Returns <Post>
    def initialize(site, base, source, image)
        /^(.*)\.[^\.]*$/ =~ image
        name = $1.downcase + '.html'

        path = source[base.size()..-1] || ''
        path = path[/^\/?[^\/]+\/(.*)$/,1] || ''

        @imageSource = source
        self.image = image
        path

        unless Post.valid? name
            filepath = File.join source, image
            date = nil
            if Kernel.const_defined? :EXIFR and /\.(jpe?g|tiff?)$/ =~ image.downcase
                ext = $1
                date = if ext[0] == 'j' then
                        EXIFR::JPEG.new(filepath).date_time
                    else
                        EXIFR::TIFF.new(filepath).date_time
                    end
            end
            if date.nil?
                File.open(filepath) { |f| date = f.ctime }
            end
            raise if date.nil?
            name = date.strftime('%Y-%m-%d-') + name
        end

        super(site, base, path, name )

        self.image_url = File.join File.dirname(self.url), self.image
    end

    # Matches a files extension
    EXT_REGEX = /\.[^\.]*$/

    # Override of Convertible::read_yaml to defer reading page information to a
    # different file other than the image.
    #
    def read_yaml(base, name)
        # defer this to another file...
        info = self.image.sub(EXT_REGEX, '.txt')
        galleryLayout = self.site.config['gallery_layout'] || 'gallery_post.html'
        if File.exists? File.join(@imageSource, info)
            super(@imageSource, info)
            self.image_info = self.content 
            self.content = nil
        else
            super(File.join(@site.source, '_layouts'), galleryLayout) if self.data.nil?
        end

        # ensure there is a layout...
        self.data['layout'] = galleryLayout.sub(EXT_REGEX, '') unless self.data.has_key? 'layout'
    end

    # Get the permalink template for galleries
    #
    def template
        self.site.config['gallery_permalink_style'] ||
            '/gallery/:categories/:title.html'
    end

    # Write the generated post file and copy the image to the destination
    # directory.
    #   +dest+ is the String path to the destination dir
    #
    # Returns nothing
    def write(dest)
        super(dest)

        # Copy the image to the dest dir
        #
        source = File.join(@imageSource, self.image)

        imageDest = destination(dest)
        imageDest = File.join(File.dirname(imageDest), self.image)

        if resize?
          target_geometry = site.config['gallery_image_geometry']
          Magick::Image.read(source).first.change_geometry(target_geometry) do |cols, rows, img|
            img.resize cols, rows
          end.write imageDest
        else
          FileUtils.cp source, imageDest
        end
    end

    def resize?
      defined?(Magick) and site.config.key?('gallery_image_geometry')
    end

    def html?; true; end

    # Convert this post into a Hash, appending GalleryPost info for use in
    # Liquid templates.
    #
    # Returns <Hash>
    def to_liquid(*args)
        super(*args).deep_merge({
            "last"  => self.last,
            "first" => self.first,
            "image" => self.image_url,
            "image_info" => self.image_info })
    end

    def first
        item = self.site.gallery.first
        if item != self
            item
        else
            nil
        end
    end

    def last
        item = self.site.gallery.last
        if item != self
            item
        else
            nil
        end
    end

    def next
      pos = self.site.gallery.index(self)

      if pos && pos < self.site.gallery.length-1
        self.site.gallery[pos+1]
      else
        nil
      end
    end

    def previous
      pos = self.site.gallery.index(self)
      if pos && pos > 0
        self.site.gallery[pos-1]
      else
        nil
      end
    end

    # Returns the object as a debug String.
    def inspect
      "#<GalleryPost @name=#{self.name.inspect}>"
    end
end

# Generates pages for each image inside of +_gallery+
#
class GalleryGenerator < Generator
    safe true

    # Does the generation
    def generate(site)
        if site.layouts.key?('gallery_post') || site.config.key?('gallery_layout')
            dir = site.config['gallery_dir'] || 'gallery'
            source = File.join site.source, '_gallery'

            site.gallery = []

            Dir.foreach_r(source) do |curDir, file|
                next unless file.downcase =~ /\.(?:png|jpe?g|bmp)$/
                site.gallery << GalleryPost.new(site, site.source, source, file)
                site.pages << site.gallery.last
            end

            site.gallery.sort!

            site.config = site.config.deep_merge({
                'gallery' => site.gallery.sort { |a, b| b <=> a },
                'gallery_old_first' => site.gallery
            })
        else
            raise
        end
    end
end

end
