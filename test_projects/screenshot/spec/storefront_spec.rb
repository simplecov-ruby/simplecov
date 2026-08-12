# frozen_string_literal: true

RSpec.describe "Storefront" do
  let(:session) { {current_user: {id: 7, name: "Ada"}} }
  let(:order_hash) do
    {
      id: 42,
      number: "ORD-000042",
      email: "ada@example.com",
      status: "paid",
      paid: true,
      expedited: true,
      total: "$48.00"
    }
  end

  it "authenticates and lists paid orders" do
    controller = OrdersController.new(session)

    result = controller.index(params: {status: "paid", page: 2}, orders: [order_hash])
    expect(result).to eq(orders: [order_hash], page: 2)
    expect(controller.show(id: 42, orders: [order_hash])[:status]).to eq(200)
  end

  it "subscribes an identified customer to order notifications" do
    channel = NotificationsChannel.new(user_id: 7)

    expect(channel.subscribed(order_id: 42)).to eq("orders:42")
    expect(channel.receive(read: false)).to eq(:ignored)
  end

  it "tracks record state and calculates an order total" do
    record = ApplicationRecord.new(id: 42)
    record.assign_attributes(status: "paid")

    expect(record[:status]).to eq("paid")
    expect(record).to be_persisted
    expect(record).to be_valid
    expect(Order.new(items: [{price_cents: 1_200, quantity: 2}], status: "paid").total_cents).to eq(2_400)
  end

  it "builds and delivers a receipt" do
    mailer = ReceiptMailer.new
    message = mailer.receipt(order_hash)

    expect(message[:subject]).to eq("Receipt for ORD-000042")
    expect(mailer.formatted_from("Storefront Orders")).to include("Storefront Orders")
    expect(ReceiptDeliveryJob.new.perform(order_hash, mailer: mailer)).to eq(:delivered)
  end

  it "formats common storefront presentation values" do
    expect(ApplicationHelper.currency(4_800)).to eq("$48.00")
    expect(ApplicationHelper.pluralize_items(2)).to eq("2 items")
    expect(ApplicationHelper.dom_id(ApplicationRecord.new(id: 42), "edit")).to eq("edit_applicationrecord_42")
    expect(OrdersHelper.status_badge("paid")).to eq("badge badge--success")
  end

  it "queues jobs and formats money" do
    ApplicationJob.perform_later(42)

    expect(ApplicationJob.queued_jobs).to eq([[42]])
    expect(MoneyFormatter.call(4_800)).to eq("$48.00")
  end
end
