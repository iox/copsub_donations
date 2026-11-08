# Kit.com (formerly ConvertKit) - our newsletter tool
#
# API key: Kit dashboard -> Account Settings -> API -> "Your API secret key"
# Docs:    https://developers.kit.com/api-reference/overview
#
# KIT_NEWSLETTER_FORM_ID is the form used by the website ("Website newsletter
# form", uid 4bc23e8de8). Donors who opt in are added to this form, so that
# they enter the form's automation / welcome emails.
#
# KIT_WEBHOOK_SECRET is the signing secret of the webhook endpoint created by
# `rake kit:setup_webhooks`. Until it is configured, incoming webhooks are
# rejected (run the rake task after deploying, then set the secret).

KIT_API_KEY = ENV['KIT_API_KEY']
KIT_NEWSLETTER_FORM_ID = (ENV['KIT_NEWSLETTER_FORM_ID'] || '10149637').to_i
