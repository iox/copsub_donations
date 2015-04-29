class ImportDonationsFromCSV

  def initialize(csv)
    @csv = csv
    @result = {
      :source => 'CSV from Bank',
      :no_user_found => [],
      :user_assigned => [],
      :multiple_users_found => [],
      :already_existing => []
    }
  end

  def import
    # encoding: 'ISO-8859-1'
    CSV.foreach(@csv.path, headers: true, col_sep: ';') do |row|
      row = row.to_hash
      if row["Beløb"].to_f > 0.0
        process_row(row)
      end
    end

    return @result
  end

  private

  def process_row(row)
    return if already_existing?(row)

    donation = prepare_donation_from_row(row)

    if donation.save
      status = AssignUserAutomatically.new(donation).try_to_assign_user
      @result[status] << donation
    else
      logger.info donation.errors.inspect
    end
  end


  def already_existing?(row)
    donation = Donation.where(:donation_method => 'bank', :bank_reference => row["Tekst"], :donated_at => row["Bogført"].to_time, :amount => row["Beløb"].to_f).first
    if donation
      @result[:already_existing] << donation
      return true
    else
      return false
    end
  end

  def prepare_donation_from_row(row)
    Donation.new(
      :bank_reference => row["Tekst"],
      :donated_at => row["Bogført"],
      :amount => row["Beløb"],
      :currency => 'DKK',
      :donation_method => 'bank'
    )
  end

end