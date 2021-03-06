require "nokogiri"

class WikipediaPagesArticleDumpParser < Nokogiri::XML::SAX::Document
  def start_document
    set_internals false
  end

  def end_document
    set_internals nil
    finish_processing
  end

  def start_element(element, attributes = [])
    @inside = element
    case element
    when "page"
      @article = {}
      @inside_page = true
    when "revision"
      @inside_revision = true
    when "redirect"
      @redirects = true
    end
  end

  def end_element(element)
    @inside = nil
    case element
    when "page"
      if not @redirects and not @namespaced and not @desambiguation and @article
        send_outside @article
        @article = nil
      end
      @redirects = false
      @inside_page = false
      @namespaced = false
      @desambiguation = false
    when "revision"
      @inside_revision = false
    when "title"

      if @inside_page and not @inside_revision
        Wikipedia::NAMESPACES.each do |ns|
          if @article["title"].match(/^#{ns}:/)
            @namespaced = true
            break
          elsif @article["title"].match(/[dD]esambigua((c|ç)(a|ã)o|ción)/)
            @desambiguation = true
            break
          end
        end
      end

    when "text"
      @desambiguation = true if @article['text'] and @article['text'].match(/\{\{[Dd]esambiguação\}\}/)
    end
  end
  
  def characters(text)
    if (["title", "id"].include? @inside and @inside_page and not @inside_revision) or (@inside == "text")
      @article[@inside] = (@article[@inside] || "") << text
    end
  end

  protected
  def set_internals(status)
    @inside_page, @inside_revision, @redirects,
      @namespaced, @desambiguation = [status] * 5
  end

  def send_outside article
    WikipediaTopicCreator.enqueue_article article
  end

  def finish_processing
    WikipediaTopicCreator.pull_articles
  end
end

module WikipediaTopicCreator
  WINDOW_SIZE = 10_000

  def self.enqueue_article(article)
    title = article.delete("title")
    @articles ||= {}
    @articles[title] = article
    self.create_topics if @articles.size > WINDOW_SIZE
  end

  def self.pull_articles
    self.create_topics unless @articles.empty?
  end

  def self.create_topics
    titles = @articles.keys.map{ |t| t.dup }

    Topic.from_titles!(titles).each do |topic|
      begin
        article = @articles.delete(topic.title)
        topic.wikipedia_pt_id = article["id"]
      rescue
        topic.wikipedia_import_status =
          if article.nil?
            Wikipedia::ImportStatus::EMPTY_ARTICLE
          else
            Wikipedia::ImportStatus::UNKNOWN_ERROR
          end
      else
        topic.wikipedia_import_status ||= Wikipedia::ImportStatus::OK
      ensure
        topic.save
      end
    end

    @articles = {}
  end
end
