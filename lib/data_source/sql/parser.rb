module GoogleDataSource
  module DataSource
    module Sql
      class ::Method; include RParsec::FunctorMixin; end
      class ::Proc; include RParsec::FunctorMixin; end

      module Parser
        include RParsec
        include Functors
        include Parsers

        extend Parsers
        # TODO drop keywords
        MyKeywords = Keywords.case_insensitive(%w{
          select from where group by having order desc asc
          inner left right full outer inner join on cross
          union all distinct as exists in between limit offset
          case when else end and or not true false
        })
        MyOperators = Operators.new(%w{+ - * / % = > < >= <= <> != : ( ) . ,})
        def self.operators(*ops)
          result = []
          ops.each do |op|
            result << (MyOperators[op] >> op.to_sym)
          end
          sum(*result)
        end
        Comparators = operators(*%w{= > < >= <= <> !=})
        quote_mapper = Proc.new do |raw|
          # is this really different to raw.gsub! ???
          raw.replace(raw.gsub(/\\'/, "'").gsub(/\\\\/, "\\"))
        end

        StringLiteral = char(?') >> ((str("\\\\")|str("\\'")|not_char(?')).many_.fragment).map(&quote_mapper) << char(?')
        QuotedName    = char(?`) >> not_char(?`).many_.fragment << char(?`)
        Variable = char(?$) >> word
        MyLexer = number.token(:number) | StringLiteral.token(:string) | Variable.token(:var) |
          QuotedName.token(:word) | MyKeywords.lexer | MyOperators.lexer
        MyLexeme = MyLexer.lexeme(whitespaces | comment_line('#')) << eof
        
        
        ######################################### utilities #########################################
        def keyword
          MyKeywords
        end

        def operator
          MyOperators
        end

        def comma
          operator[',']
        end

        def list expr
          paren(expr.delimited(comma))
        end

        def word(&block)
          if block.nil?
            token(:word, &Id)
          else
            token(:word, &block)
          end
        end 

        def paren parser
          operator['('] >> parser << operator[')']
        end

        def ctor cls
          cls.method :new
        end

        def rctor cls, arity=2
          ctor(cls).reverse_curry arity
        end

        ################################### predicate parser #############################
        def logical_operator op
          proc{|a,b|CompoundPredicate.new(a,op,b)}
        end

        def make_predicate expr, rel
          expr_list = list expr
          comparison = make_comparison_predicate expr, rel
          group_comparison = sequence(expr_list, Comparators, expr_list, &ctor(GroupComparisonPredicate))
          bool = nil
          lazy_bool = lazy{bool}
          bool_term = keyword[:true] >> true | keyword[:false] >> false |
            comparison | group_comparison | paren(lazy_bool) |
            make_exists(rel) | make_not_exists(rel)
          bool_table = OperatorTable.new.
            infixl(keyword[:or] >> logical_operator(:or), 20).
            infixl(keyword[:and] >> logical_operator(:and), 30).
            prefix(keyword[:not] >> ctor(NotPredicate), 40)
          bool = Expressions.build(bool_term, bool_table)
        end

        def make_exists rel
          keyword[:exists] >> rel.map(&ctor(ExistsPredicate))
        end

        def make_not_exists rel
          keyword[:not] >> keyword[:exists] >> rel.map(&ctor(NotExistsPredicate))
        end

        def make_in expr
          keyword[:in] >> list(expr) >> map(&rctor(InPredicate))
        end

        def make_not_in expr
          keyword[:not] >> keyword[:in] >> list(expr) >> map(&rctor(NotInPredicate))
        end

        def make_in_relation rel
          keyword[:in] >> rel.map(&rctor(InRelationPredicate))
        end

        def make_not_in_relation rel
          keyword[:not] >> keyword[:in] >> rel.map(&rctor(NotInRelationPredicate))
        end

        def make_between expr
          make_between_clause(expr, &ctor(BetweenPredicate))
        end

        def make_not_between expr
          keyword[:not] >> make_between_clause(expr, &ctor(NotBetweenPredicate))
        end

        def make_comparison_predicate expr, rel
          comparison = sequence(Comparators, expr) do |op,e2|
            proc{|e1|ComparePredicate.new(e1, op, e2)}
          end
          in_clause = make_in expr
          not_in_clause = make_not_in expr
          in_relation = make_in_relation rel
          not_in_relation = make_not_in_relation rel
          between = make_between expr
          not_between = make_not_between expr
          compare_with = comparison | in_clause | not_in_clause |
              in_relation | not_in_relation | between | not_between
          sequence(expr, compare_with, &Feed)
        end

        def make_between_clause expr, &maker
          factory = proc do |a,_,b|
            proc {|v|maker.call(v,a,b)}
          end
          variant1 = keyword[:between] >> paren(sequence(expr, comma, expr, &factory))
          variant2 = keyword[:between] >> sequence(expr, keyword[:and], expr, &factory)
          variant1 | variant2
        end
        
        ################################ expression parser ###############################
        def calculate_simple_cases(val, cases, default)
          SimpleCaseExpr.new(val, cases, default)
        end

        def calculate_full_cases(cases, default)
          CaseExpr.new(cases, default)
        end

        def make_expression predicate, rel
          expr = nil
          lazy_expr = lazy{expr}

          wildcard = operator[:*] >> WildcardExpr::Instance
          lit = token(:number, :string, &ctor(LiteralExpr)) | token(:var, &ctor(VarExpr))
          atom = lit | wildcard | word(&ctor(WordExpr))
          term = atom | (operator['('] >> lazy_expr << operator[')'])

          table = OperatorTable.new.
            infixl(operator['+'] >> Plus, 20).
            infixl(operator['-'] >> Minus, 20).
            infixl(operator['*'] >> Mul, 30).
            infixl(operator['/'] >> Div, 30).
            infixl(operator['%'] >> Mod, 30).
            prefix(operator['-'] >> Neg, 50)
          expr = Expressions.build(term, table)
        end
        
        ################################ relation parser ###############################
        def make_relation expr, pred
          where_clause = keyword[:where] >> pred
          order_element = sequence(expr, (keyword[:asc] >> true | keyword[:desc] >> false).optional(true),
            &ctor(OrderElement))
          order_elements = order_element.separated1(comma)
          exprs = expr.separated1(comma)

          # setup clauses
          select_clause = keyword[:select] >> exprs
          order_by_clause = keyword[:order] >> keyword[:by] >> order_elements
          group_by = keyword[:group] >> keyword[:by] >> exprs
          group_by_clause = sequence(group_by, (keyword[:having] >> pred).optional, &ctor(GroupByClause))
          limit_clause = keyword[:limit] >> token(:number, &To_i)
          offset_clause = keyword[:offset] >> token(:number, &To_i)

          # build relation
          relation = sequence(
            select_clause.optional([WildcardExpr.new]),
            where_clause.optional, group_by_clause.optional, order_by_clause.optional,
            limit_clause.optional, offset_clause.optional
          ) do |select, where, groupby, orderby, limit, offset|
            SelectRelation.new(select, where, groupby, orderby, limit, offset)
          end
        end
        
        ########################## put together ###############################
        def expression
          assemble[0]
        end

        def relation
          assemble[2]
        end
        def predicate
          assemble[1]
        end
        
        def assemble
          pred = nil
          rel = nil
          lazy_predicate = lazy{pred}
          lazy_rel = lazy{rel}
          expr = make_expression lazy_predicate, lazy_rel
          pred = make_predicate expr, lazy_rel
          rel = make_relation expr, pred
          return expr, pred, rel
        end
        
        def make parser
          MyLexeme.nested(parser << eof)
        end
      end
    end
  end
end
