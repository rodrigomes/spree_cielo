# coding: utf-8

Spree::CheckoutController.class_eval do
  prepend_before_filter :request_authorization_at_cielo_hosted_page

  def cielo_callback
    if current_cielo_payment
      if @order.next
        state_callback :after
        if @order.state == 'complete' || @order.completed?
          flash.notice = t :order_processed_successfully
          flash[:commerce_tracking] = 'nothing special'
          redirect_to completion_route
          return
        end
      else
        flash[:error] = "Houve um problema com o pagamento"
        if current_order.payments.first.source.status == :nao_autorizada then
          flash[:error2] = "Pagamento não autorizado"
        end
        @order.errors.messages.each do |field,errors|
          flash[field] = "#{field.to_s.titleize} #{errors.join ", "}"
        end
      end
    end
    redirect_to checkout_state_path @order.state
  end

  private
  def is_cielo? payment_method
    payment_method.is_a? SpreeCielo::HostedBuyPagePayment::Gateway and payment_method
  end

  def before_payment
    # disables spree default behavior that erases previous payment history
    # current_order.payments.destroy_all if request.put?
  end

  def request_authorization_at_cielo_hosted_page
    return unless request.put? and
      params[:state] == "payment" and
      method = is_cielo?(payment_method_from_params)

    url = checkout_state_path @order.state
    if payment.valid?
      callback_url = request.url.gsub request.path, cielo_callback_pat
      txn = method.authorization_transaction @order, payment.source, callback_url

      if txn and txn.success?
        url = txn.url_autenticacao
        payment.response_code = txn.tid
        payment.save
      else
        flash.keep[:payment] = "Pagamento não foi salvo"
      end

      fire_event 'spree.checkout.update'
    end
    redirect_to url
  end

  def payment_method_from_params
    load_order
    if @payment_params = object_params[:payments_attributes].first
      if method_id = @payment_params[:payment_method_id]
        Spree::PaymentMethod.find method_id
      end
    end
  end

  def payment
    return @payment unless @payment.nil?

    @payment = current_cielo_payment
    if @payment
      @payment.update_attributes @payment_params

      # nested source_attributes were ignored on update! (dafuk!?), reasoning this line
      @payment.source.update_attributes @payment_params[:source_attributes]
      @payment
    else
      @payment = @order.payments.create @payment_params
    end
  end

  def current_cielo_payment
    @order.payments.detect { |p|
      p.checkout? and is_cielo? p.payment_method
    }
  end
end
