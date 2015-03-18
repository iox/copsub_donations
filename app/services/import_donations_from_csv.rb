class ImportDonationsFromCSV

  def initialize(csv)
    @csv = csv
    @imported_donations = []
    @already_existing_donations = []
    @message = ""
  end

  def import
    # encoding: 'ISO-8859-1'
    CSV.foreach(@csv.path, headers: true, col_sep: ';') do |row|
      donation = row.to_hash
      if donation["Beløb"].to_f > 0.0
        existing_donation = Donation.where(:donation_method => 'bank', :bank_reference => donation["Tekst"], :donated_at => donation["Bogført"].to_time, :amount => donation["Beløb"].to_f).first
        if existing_donation
          @already_existing_donations << donation
        else
          @imported_donations << donation
          donation = Donation.new(
            :bank_reference => donation["Tekst"],
            :donated_at => donation["Bogført"],
            :amount => donation["Beløb"],
            :currency => 'DKK',
            :donation_method => 'bank'
          )
          if !donation.save
            logger.info donation.errors.inspect
          else
            @message += "<br/> - Donation #{donation.id}, amount #{donation.amount}, bank reference #{donation.bank_reference} imported"
            @message += "<strong>User found: #{donation.wordpress_user_id}</strong>" if donation.wordpress_user_id
          end
        end
      end
    end

    return {
      :imported_donations => @imported_donations,
      :already_existing_donations => @already_existing_donations,
      :message => @message
    }
  end

end