class Customer < ApplicationRecord
  def self.email_from_case(kase)
    customer = find_by_desk_id(kase.id)
    return customer.email if customer

    emails = DeskApi.customers.find(kase.customer.id).emails
    email_hash = Hash[
      emails.collect { |email| [email['type'], email['value']] }
    ].with_indifferent_access
    email = email_hash[:home] || email_hash[:work] || email_hash[:other]
    create(desk_id: kase.id, email: email).email
  end
end
