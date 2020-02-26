module Freshdesk
  class TestRateLimits < Base
    step :init
    step :test
    step :complete

    failed :log_failure

    def test
      ticket = freshdesk_post(
        'tickets',
        email:        "foobar-#{rand(10000)}@gmail.com",
        subject:      "this is a bogus ticket",
        status:       5,
        priority:     1, # this is required!
        responder_id: nil,
        description:  'this is a bogus ticket body',
        tags:         ['RATE-LIMIT-TEST']
      )
      4.times do |n|
        freshdesk_add_note(ticket[:id], "note #{n} added here")
      end
    end
  end
end
