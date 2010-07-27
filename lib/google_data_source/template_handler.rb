# A simple template handler for a data source
# Provides a GoogleDataSource::Base object datasource in the template so the template
# can fill it with data
module GoogleDataSource
  class TemplateHandler < ActionView::TemplateHandler
    include ActionView::TemplateHandlers::Compilable

    def compile(template)
      <<-EOT
      datasource = GoogleDataSource::Base.from_params(params)
      #{template.source.dup}
      datasource.response
      EOT
    end
  end
end
