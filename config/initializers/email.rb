ActionMailer::Base.delivery_method = :smtp
ActionMailer::Base.smtp_settings = {
 :address               => "send.one.com",
 :port                  => 465,
 :domain                => "copenhagensuborbitals.com",
 :user_name             => "no-reply@copsub.com",
 :password              => "sputnikapollo",
 :authentication        => :plain,
 :enable_starttls_auto  => false,
 :ssl                   => true
}