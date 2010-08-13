module GoogleDataSource
  module DataSource
    # A simple template handler for a data source
    # Provides a GoogleDataSource::Base object datasource in the template so the template
    # can fill it with data
    class TemplateHandler < ActionView::TemplateHandler
      include ActionView::TemplateHandlers::Compilable

      def compile(template)
        <<-EOT
        datasource = GoogleDataSource::DataSource::Base.from_params(params)
        #{template.source.dup}
        datasource.callback = "$('\\\#\#{datasource.reporting.form_id}').html(\#{render(:partial => datasource.reporting.partial).to_json});" unless datasource.reporting.nil?
        datasource.response
        EOT
      end
    end
  end
end
