# frozen_string_literal: true

module StorefrontFixture
  SourceFile = Struct.new(:path, :source, keyword_init: true)

  FILES = [
    SourceFile.new(path: "app/controllers/application_controller.rb", source: <<~'RUBY'),
      # frozen_string_literal: true

      class ApplicationController
        AuthenticationError = Class.new(StandardError)

        attr_reader :current_user

        def initialize(session = {})
          @session = session
          @current_user = session[:current_user]
        end

        def authenticate!
          return current_user if current_user

          Rails.logger.warn("Authentication required") # simplecov:disable line -- Rails logger integration
          raise AuthenticationError, "Please sign in"
        end

        def page_from(params)
          page = params.fetch(:page, 1).to_i
          page.positive? ? page : 1
        end

        def per_page_from(params)
          [params.fetch(:per_page, 25).to_i, 100].min
        end
      end
    RUBY
    SourceFile.new(path: "app/controllers/orders_controller.rb", source: <<~'RUBY'),
      # frozen_string_literal: true

      class OrdersController < ApplicationController
        def index(params:, orders:)
          authenticate!
          visible = params[:status] ? orders.select { |order| order[:status] == params[:status] } : orders
          {orders: visible, page: page_from(params)}
        end

        def show(id:, orders:)
          order = orders.find { |candidate| candidate[:id] == id }
          return {order: order, status: 200} if order

          Rails.logger.info("Order #{id} was not found") # simplecov:disable line -- Rails logger integration
          {error: "Order not found", status: 404}
        end

        def create(params:)
          total_cents = params.fetch(:total_cents, 0).to_i
          return {error: "Total must be positive", status: 422} unless total_cents.positive?

          {order: params.merge(total_cents: total_cents), status: 201}
        end
      end
    RUBY
    SourceFile.new(path: "app/channels/application_cable/channel.rb", source: <<~'RUBY'),
      # frozen_string_literal: true

      module ApplicationCable
        class Channel
          attr_reader :connection

          def initialize(connection = {})
            @connection = connection
          end

          def identified?
            connection[:user_id] ? true : false
          end

          def reject_unauthorized_connection
            return true if identified?

            Rails.logger.warn("Rejected unidentified cable connection") # simplecov:disable line -- Rails logger integration
            raise "Unauthorized connection"
          end

          def transmit(payload)
            connection[:messages] ||= []
            connection[:messages] << payload
          end
        end
      end
    RUBY
    SourceFile.new(path: "app/channels/notifications_channel.rb", source: <<~'RUBY'),
      # frozen_string_literal: true

      class NotificationsChannel < ApplicationCable::Channel
        attr_reader :stream

        def subscribed(order_id:)
          reject_unauthorized_connection
          @stream = "orders:#{order_id}"
        end

        def receive(data)
          return :ignored unless data[:read]

          transmit(type: "notification.read", id: data[:id])
        end

        def unsubscribed
          previous_stream = stream
          Rails.logger.debug("Unsubscribing from #{previous_stream}") # simplecov:disable line -- Rails logger integration
          @stream = nil
          previous_stream ? :stopped : :idle
        end
      end
    RUBY
    SourceFile.new(path: "app/models/application_record.rb", source: <<~'RUBY'),
      # frozen_string_literal: true

      class ApplicationRecord
        attr_reader :attributes

        def initialize(attributes = {})
          @attributes = attributes.dup
        end

        def [](name)
          attributes[name]
        end

        def persisted?
          attributes.key?(:id) ? true : false
        end

        def valid?
          errors.empty? ? true : false
        end

        def errors
          attributes.fetch(:errors, [])
        end

        def assign_attributes(changes)
          changes.each { |name, value| attributes[name] = value }
          self
        end
      end
    RUBY
    SourceFile.new(path: "app/models/order.rb", source: <<~'RUBY'),
      # frozen_string_literal: true

      class Order < ApplicationRecord
        def total_cents
          self[:items].sum { |item| item[:price_cents] * item.fetch(:quantity, 1) }
        end

        def paid?
          self[:status] == "paid"
        end

        def refundable?
          paid? && total_cents.positive?
        end

        def cancel!
          if paid?
            errors << "Paid orders cannot be cancelled"
          else
            attributes[:status] = "cancelled"
          end
          valid?
        end

        def display_number
          "ORD-#{self[:id].to_s.rjust(6, '0')}"
        end
      end
    RUBY
    SourceFile.new(path: "app/mailers/application_mailer.rb", source: <<~'RUBY'),
      # frozen_string_literal: true

      class ApplicationMailer
        DEFAULT_FROM = "Storefront <orders@example.test>"

        attr_reader :deliveries

        def initialize
          @deliveries = []
        end

        def mail(to:, subject:, body:)
          raise ArgumentError, "recipient is required" if to.to_s.empty?

          message = {from: DEFAULT_FROM, to: to, subject: subject, body: body}
          deliveries << message
          message
        end

        def formatted_from(name = nil)
          name ? "#{name} <orders@example.test>" : DEFAULT_FROM
        end

        def delivery_count
          deliveries.length
        end
      end
    RUBY
    SourceFile.new(path: "app/mailers/receipt_mailer.rb", source: <<~'RUBY'),
      # frozen_string_literal: true

      class ReceiptMailer < ApplicationMailer
        def receipt(order)
          mail(
            to: order[:email],
            subject: "Receipt for #{order[:number]}",
            body: body_for(order)
          )
        end

        def refund(order)
          mail(to: order[:email], subject: "Refund issued", body: "Your refund is on its way.")
        end

        private

        def body_for(order)
          shipping = order[:expedited] ? "expedited" : "standard"
          "Thanks for your #{shipping} order of #{order[:total]}."
        end

        def internal_copy?(order)
          order[:email].end_with?("@example.test")
        end
      end
    RUBY
    SourceFile.new(path: "app/helpers/application_helper.rb", source: <<~'RUBY'),
      # frozen_string_literal: true

      module ApplicationHelper
        module_function

        def currency(cents)
          format("$%.2f", cents.to_i / 100.0)
        end

        def pluralize_items(count)
          noun = count == 1 ? "item" : "items"
          "#{count} #{noun}"
        end

        def dom_id(record, prefix = nil)
          base = "#{record.class.name.downcase}_#{record[:id]}"
          prefix ? "#{prefix}_#{base}" : base
        end

        def page_title(title = nil)
          title ? "#{title} · Storefront" : "Storefront"
        end
      end
    RUBY
    SourceFile.new(path: "app/helpers/orders_helper.rb", source: <<~'RUBY'),
      # frozen_string_literal: true

      module OrdersHelper
        module_function

        def status_badge(status)
          case status.to_s
          when "paid" then "badge badge--success"
          when "pending" then "badge badge--warning"
          when "cancelled" then "badge badge--muted"
          else
            Rails.logger.debug("Unknown order status: #{status}") # simplecov:disable line -- Rails logger integration
            "badge"
          end
        end

        def order_heading(order)
          "Order #{order[:number]} for #{order[:customer_name]}"
        end

        def delivery_estimate(expedited: false)
          expedited ? "1–2 business days" : "3–5 business days"
        end

        def gift_note(order)
          order[:gift] ? "A gift for #{order[:recipient]}" : nil
        end
      end
    RUBY
    SourceFile.new(path: "app/jobs/application_job.rb", source: <<~'RUBY'),
      # frozen_string_literal: true

      class ApplicationJob
        class << self
          attr_reader :queued_jobs

          def perform_later(*arguments)
            @queued_jobs ||= []
            @queued_jobs << arguments
          end

          def queue_name
            name.end_with?("MailerJob") ? "mailers" : "default"
          end

          def clear_queue
            @queued_jobs = []
          end
        end

        def retryable?(error)
          error.is_a?(Timeout::Error) ? true : false
        end
      end
    RUBY
    SourceFile.new(path: "app/jobs/receipt_delivery_job.rb", source: <<~'RUBY'),
      # frozen_string_literal: true

      class ReceiptDeliveryJob < ApplicationJob
        def perform(order, mailer: ReceiptMailer.new)
          return :skipped unless order[:paid]

          mailer.receipt(order)
          :delivered
        end

        def attempts_for(error)
          retryable?(error) ? 5 : 1
        end

        def discard?(error)
          error.is_a?(ArgumentError)
        end

        def audit_payload(order)
          {job: self.class.name, order_id: order[:id], paid: order[:paid]}
        end
      end
    RUBY
    SourceFile.new(path: "lib/money_formatter.rb", source: <<~'RUBY'),
      # frozen_string_literal: true

      module MoneyFormatter
        module_function

        def call(cents, currency: "USD")
          amount = format("%.2f", cents.to_i / 100.0)
          currency == "USD" ? "$#{amount}" : "#{amount} #{currency}"
        end

        def accounting(cents)
          value = call(cents.abs)
          cents.negative? ? "(#{value})" : value
        end

        def compact(cents)
          return call(cents) if cents.abs < 100_000

          format("$%.1fk", cents / 100_000.0)
        end

        def parse(value)
          (value.to_s.delete("$, ").to_f * 100).round
        end
      end
    RUBY
    SourceFile.new(path: "lib/order_number.rb", source: <<~'RUBY')
      # frozen_string_literal: true

      module OrderNumber
        PREFIX = "ORD"
        module_function

        def generate(sequence)
          "#{PREFIX}-#{sequence.to_i.to_s.rjust(6, '0')}"
        end

        def valid?(value)
          value.to_s.match?(/\A#{PREFIX}-\d{6}\z/)
        end

        def sequence(value)
          return unless valid?(value)

          value.split("-").last.to_i
        end

        def next_after(value)
          generate(sequence(value) + 1)
        end
      end
    RUBY
  ].freeze

  REQUIRED_PATHS = FILES.map(&:path) - ["lib/order_number.rb"]
end
